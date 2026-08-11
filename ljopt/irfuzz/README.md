# ljopt IR-optimizer fuzzer

A deterministic, seed-driven fuzzer that stress-tests LuaJIT's trace
optimizer (the FOLD engine and its load/store forwarding) by checking,
for thousands of synthetic IR traces, that optimizing a trace never
changes its observable result. It reuses ljopt's existing SMT
equivalence oracle, so a finding is either a real optimizer miscompile
or a modelling gap in ljopt — never a false alarm about a run that
didn't happen.

## How it works

```
seed ──► gen.lua ──► spec ──► jit.util.irfuzz ──► (unopt buf, opt buf)
                                                        │
                          decode.lua ◄──────────────────┘
                                │  (two recorded-shaped trace_records)
                          check.lua
                                │  attach final snapshot over outputs
                                ▼
             ir_smtlib.compare_trace_records  ──►  SMT
                                                    │
                                              z3 (fuzz.lua)
                                                    ▼
                              unsat = equivalent    sat = divergence
```

1. **`gen.lua` — generate.** From an integer seed (via a small
   reproducible LCG, never `math.random`) it emits a synthetic, typed
   SSA-IR instruction stream: a few `SLOAD` inputs, `KINT`/`KNUM`
   constants, and a body of pure arithmetic / bitwise / table ops. The
   op menu is **blacklist-based** — the full set the recorder can emit
   for each type, minus documented exclusions (`RECORDER_IMPOSSIBLE`
   for op+type the JIT never emits, `KNOWN_LJOPT_GAP` for ops ljopt
   models incompletely). It returns the stream plus the *outputs* — the
   last live value ref of each type, which are what we prove equal.

2. **`jit.util.irfuzz` (C, added by
   `lua_patches/luajit-v2.1-jit_util_irfuzz.patch`) — replay.** Feeds
   the stream through the real FOLD engine twice: once with all
   optimizations off (`-O0`) and once with `JIT_F_OPT_DEFAULT` (`-O3`).
   It returns both IR buffers as flat numeric arrays plus a `map` from
   generator ref → resulting IR ref in each pass. No bytecode, no
   assembly — just the optimizer.

3. **`decode.lua` — rebuild.** Turns each replayed buffer back into the
   `trace_record` node table that `ir_smtlib` consumes, byte-identical
   to what the recorded path produces (same `float_to_smt_bv`, same
   operand decode as `ir_dump.lua`).

4. **`check.lua` — glue + classify.** Marks any output ljopt can't
   model (NYI node or uninterpreted op such as `POW`) as a *coverage
   gap* and drops it from the comparison. It attaches one final
   snapshot capturing the surviving outputs into stack slots, then
   hands the two trace_records to
   `ir_smtlib.compare_trace_records` — the *same* oracle the recorded
   path uses. No SMT lives here.

5. **`fuzz.lua` — drive.** Runs the solver on each query (standalone
   binary, so
   one crash/timeout can't sink the run) and reports every `sat` with
   its seed.

The optimized and un-optimized traces run through identical translation,
so if they diverge in the SMT it is because the optimizer changed an
observable value: `unsat` ⇒ the optimizer preserved observable state,
`sat` ⇒ a candidate miscompile (or an ljopt modelling gap — triage by
`--show`).

## Usage

Needs a solver binary — cvc5 by default, z3 with `LJOPT_SOLVER=z3`
(see repo `CLAUDE.md`) — and
the luajit fork with the irfuzz patch applied (the `make`-built
`build/luajit_<tag>` already has it).

```sh
# One seed: dump both IR traces and the full SMT query.
luajit ljopt/irfuzz/fuzz.lua --show 17

# Sweep: check N seeds starting at S; prints SAT <seed> for candidates.
luajit ljopt/irfuzz/fuzz.lua --seed 1 --count 5000

# Also generate table/array memory ops (AREF/HREF/ALOAD/HLOAD/…).
luajit ljopt/irfuzz/fuzz.lua --tables --seed 1 --count 2000

# Replay as a loop trace: the optimized pass also runs lj_opt_loop,
# so the sweep covers unrolling and PHIs (ljopt unrolls both sides).
luajit ljopt/irfuzz/fuzz.lua --loop --enum --type num --depth 1

# Also generate ops ljopt models incompletely, to hunt ljopt gaps
# rather than LuaJIT miscompiles.
luajit ljopt/irfuzz/fuzz.lua --include-gaps --seed 1 --count 2000

# FP narrowing: num ADD/SUB trees converted back to an integer, the
# only shape that reaches lj_opt_narrow.c from an IR replay.
luajit ljopt/irfuzz/fuzz.lua --narrow --limit 2000

# Allocation sinking: stores into a TNEW the trace created itself,
# the only shape that makes lj_opt_sink.c do anything.
luajit ljopt/irfuzz/fuzz.lua --sink

# String buffers: the BUFHDR/BUFPUT/BUFSTR chain Lua's `..` records
# as, and the only way into lj_opt_fold.c's buffer rules.
luajit ljopt/irfuzz/fuzz.lua --buffers

# Exhaustive mode: walk EVERY depth-D op chain over the SLOAD inputs
# and the fold-rule constants (enum.lua), instead of random seeds.
luajit ljopt/irfuzz/fuzz.lua --enum --type int --depth 1
luajit ljopt/irfuzz/fuzz.lua --enum --type num --depth 2 --limit 20000

# Reproduce an exhaustive-mode finding by its enumeration index.
luajit ljopt/irfuzz/fuzz.lua --enum --type num --depth 2 --show 1234
```

Flags: `--seed S`, `--count N`, `--insns K` (body length), `--no-ints`
(num only), `--include-gaps`, `--tables`, `--show SEED`.
Exhaustive mode: `--enum`, `--type num|int`, `--depth D` (chain
length), `--ninputs N` (#SLOADs), `--limit L`, `--skip K` (resume
offset), `--show I` (I = enumeration index).

Tuning env vars: `LJOPT_SOLVER` (`cvc5` default, or `z3`),
`LJOPT_CVC5_BIN` (default `../cvc5/build/bin/cvc5`),
`LJOPT_Z3_BIN` (default `../z3/build/z3`),
`LJOPT_Z3_TIMEOUT` (seconds, default 15).

Every seed is a pure function of its number, so any `SAT seed=N`
reproduces exactly with `--show N`. Enumeration order is likewise
deterministic for fixed `--type/--depth/--ninputs`, so `SAT #I`
reproduces with the printed `--enum ... --show I`.

### Exhaustive mode (`--enum`)

Random sampling only fires a constant-guarded fold when the dice land
on the right constant; `enum.lua` instead walks the full cross product
of (op, operands) for a linear chain of `--depth` ops, where operands
are the `--ninputs` SLOADs plus every fold-rule constant. Every
constant-triggered fold in that space fires at least once. The space
is `|ops|^depth * |leaves|^(depth+1)` and explodes fast (num depth=3
is ~12.5M), so the driver prints the total up front and `--limit` /
`--skip` bound and resume a run.

Two sound filters keep z3 out of the no-op cases: traces the
optimizer left **byte-identical** are counted and skipped, as are
traces differing **only by operand swaps of provably-commutative ops**
(fp.add/fp.mul under one rounding mode, int ADD/MUL/BAND/BOR/BXOR —
fold's `k + x -> x + k` canonicalization; z3 burns ~30s per FP query
re-proving commutativity). MIN/MAX are *not* in that set: SMT
`fp.min`/`fp.max` are underspecified on `(+0,-0)`, so their operand
order still goes to z3.

## Instruction coverage

- **Arithmetic** — binary num (`ADD SUB MUL DIV MOD POW MIN MAX`), int
  (`ADD SUB MUL DIV MOD`, `BAND BOR BXOR`, shifts, rotates); unary num
  `NEG`/`ABS`, unary int `NEG`/`BNOT`/`BSWAP`; `FPMATH` rounding modes
  and `LDEXP`.
- **FP narrowing** (`--narrow`) — `CONV`/`TOBIT` sinks over num
  `ADD`/`SUB` trees whose leaves are `CONV num<-int`, overflow-checked
  `ADDOV`/`SUBOV`/`MULOV`, FP constants across the `checki16` and
  int64 range tests, and non-narrowable num `SLOAD`s. This is the
  only shape that reaches `lj_opt_narrow.c` from an IR replay — every
  other entry point there is called by the recorder. Two sinks are
  deliberately excluded as recorder-impossible in isolation; see the
  comments on `NARROW_SINKS` in `enum.lua`.
- **Allocation sinking** (`--sink`) — `TNEW` plus stores addressed
  through `AREF` (constant and loaded index), `NEWREF` and an
  `SLOAD`'d table, under the shapes that decide eligibility in
  `sink_mark_ins`: a snapshot-live allocation, a surviving load, a
  `TBAR`, an `FLOAD tab.meta`, and the allocation used as a stored
  value. Sinking itself is *covered but not verified* — its result
  lives in `ir->prev`, which never reaches the decoded IR; what the
  sweep does verify is FOLD and `lj_opt_mem.c` on a trace-local
  table. See the comment on `SINK_ALLOCS` in `enum.lua`.
- **String buffers** (`--buffers`) — `BUFHDR`/`BUFPUT`/`BUFSTR`
  chains and `CALLL lj_buf_putstr_reverse`, over constant and
  symbolic strings: constant-put joining, empty puts, the one-put
  shortcut, `BUFSTR` spliced back into a following `BUFHDR`, and
  whole-chain CSE. ljopt models a buffer as a string cell and a put
  as `str.++`, so this is a value oracle and not only coverage.
- **Tables / arrays** (`--tables`) — `SLOAD tab`, `FLOAD tab.array`,
  `AREF`/`HREF`, `ALOAD`/`HLOAD`, `ASTORE`/`HSTORE`. Array indices and
  hash keys are drawn from disjoint value ranges (positive vs negative
  ints) because LuaJIT's array and hash parts are separate address
  spaces and ljopt keys both by value.

### Known limitation

`--tables` with repeated or dead stores to an *escaping* (SLOAD'd)
table can produce a spurious `sat` from ljopt's memory-diff encoding
(the final-version comparison over the shared memory array), not from a
real optimizer bug. This is an ljopt modelling gap, not a LuaJIT
miscompile; narrowing generation or extending the memory-diff is
tracked as follow-up work.
