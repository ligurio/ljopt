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

## Optimizer coverage

The `covrun.lua` driver runs one mode against a gcov-instrumented
LuaJIT and skips the solver, so the counters show which optimizer
paths the generator reaches. Build it with `LUAJIT_ENABLE_COVERAGE=ON`
and report with the gcov matching the compiler (`gcov-11` for gcc 11):

```sh
COV_JITOFF=1 LUA_PATH="./?/init.lua;;" \
  build/luajit_cov/src/luajit ljopt/irfuzz/covrun.lua <mode> [limit]
```

`COV_JITOFF=1` is required for every mode but `recorded`: without it
the host JIT compiles ljopt's own Lua and pollutes the counters.
`COV_LOOP=1` replays each trace as a loop, which is what reaches
`lj_opt_loop.c` and the PHI paths.

The full sweep (every mode, with and without `COV_LOOP`, each
capped at 8000 traces) currently covers 2448 of 2513 lines, 97.4%:

| file | lines | hit | |
|---|---|---|---|
| `lj_opt_fold.c`   | 1241 | 1209 | 97.4% |
| `lj_opt_mem.c`    |  572 |  554 | 96.9% |
| `lj_opt_loop.c`   |  245 |  238 | 97.1% |
| `lj_opt_dce.c`    |   35 |   35 | 100%  |
| `lj_opt_sink.c`   |  148 |  145 | 98.0% |
| `lj_opt_narrow.c` |  272 |  267 | 98.2% |

The `COV_LOOP` half of that only works against a LuaJIT built from
the *current* `lua_patches`. `make` rebuilds `build/luajit_<tag>/`
only when the directory is missing, so a build that predates the
loop-replay patch still runs and silently ignores `spec.loop` --
`grep -c "lj_opt_loop(J)" build/luajit_<tag>/src/lib_jit.c` must
print 1.

Sixteen of the 65 lines left are unreachable by construction:

- `lj_opt_fold.c` 286, 358, 389, 489, 2017 -- `default:` arms behind
  an `lj_assert*`, i.e. "cannot happen".
- `lj_opt_fold.c` 386 -- the `IR_BSAR` case of `kfold_int64arith`. No
  fold rule passes BSAR to it: `simplify_shiftk_andk` is keyed on
  BSHL, BSHR, BROL and BROR only.
- `lj_opt_fold.c` 2219, 2229, 2246, 2262, 2271, 2282 -- the "folding
  disabled" arm of the constant-object load rules. With FOLD off,
  `lj_opt_fold` emits loads raw (`lj_opt_fold.c:2452`) and never
  reaches the fold table, so the arm cannot run at any -O level.
- `lj_opt_mem.c` 240 -- the fall-through after `tvispri` / `tvisnum`
  / `tvisint` / `tvisgcv`, which is every TValue type.
- `lj_opt_mem.c` 578, 579, 581 -- the redundant-FSTORE elimination.
  The recorder emits exactly two FSTOREs: `tab.meta`, always preceded
  by the `FLOAD tab.meta` of the `__metatable` check that the scan
  treats as a conflict, and `tab.nomm`, always storing the same
  constant 0, so the equal-value store is dropped before the
  elimination is considered.

`lj_opt_loop.c` 374 -- the redundant-snapshot drop -- is reached by
the `loop_snap_drop` chunk. It needs a loop whose back-edge is
unconditional, so the exit test is not the last guard, and whose
tail is FP-only: the LOOP marker is itself a guard, only a snapshot
substitution clears `J->guardemit`, and an int counter's `ADDOV`
re-arms it after that snapshot.

`lj_opt_loop.c` 183-185 is pass #4's mark propagation, and needs a
PHI whose right ref is a *still-marked* PHI. A mark is set in pass
#1 when the right ref is not a simple recurrence, and cleared in
pass #2 for every ref used as an operand in the variant part, so
the marked PHI has to be consumed by nothing but another PHI's
right ref. Copy chains between carried slots (`a, b = b, f(a)`, and
longer rotations) do not do it: they never set `passx`, so the pass
does not run at all.

`lj_opt_loop.c` 167 -- pass #3's `LJ_TRERR_PHIOV` -- is reached by
the `licm` mode. Crossing `LJ_MAX_PHI` (64) anywhere but the raise
in the main slot walk needs an extra PHI from somewhere else, and
the loop pass's type coercion supplies one: a slot whose SLOAD type
differs from the value written back has to be converted, and the
conversion promotes its operand. 65 slots with the top one mistyped
crosses the limit in pass #3; more than that trips the main raise
first. 366, the same raise on the phiconv path, still needs a
carried CONV whose operand is loop-invariant.

That mode is the one place the harness writes a slot a value of the
wrong type on purpose, so it passes `raw_slots` to keep
`gen.loop_order` from correcting it, and it is coverage-only -- the
mistyped wiring is exactly what makes a comparison unsound.

`lj_opt_loop.c` 349 -- the loop pass converting a carried slot back
to int -- was covered before the outputs were type-ordered, and
only because of that: it needs the snapshot's slot type to differ
from the loop-end value's type, and once each slot is fed a value
of its own type those are the same ref. Recovering it needs the
*substituted* value's type to differ from the snapshot's, which no
shape here produces yet. Trading it for an oracle that does not
report false divergences is the right way round, but it is a trade.

`lj_opt_loop.c` 395 -- `loop_undo`'s backprop-cache purge -- cannot
be reached from the replay at all today, and not for want of a
shape: `irfuzz_reset` never initializes `J->instunroll`, which the
recorder sets from `J->param[JIT_P_instunroll]`. A failed unroll
therefore takes the `--J->instunroll < 0` break and propagates the
error instead of calling `loop_undo`, so every `loop_undo` in the
counters comes from `recorded` mode. Beyond initializing it, the
line wants a cache entry created *during* the copy -- so a narrowed
CONV emitted there -- and then a failure after it, which points at
FAILFOLD/GFAIL mid-copy rather than the type instability the slot
walk reports, since that aborts before the copy narrows anything.

Of the rest, one needs a harness change rather than a new shape:
`lj_opt_mem.c` 642-644 folds two `KPTR` bases into base vs.
base+offset, and the replay spec has no constant-pointer operand
kind (`gen.kinds` stops at `KSTR`), so no shape can produce that
pair. `lj_opt_narrow.c` 257-259 is the backtrack after
`narrow_conv_backprop` overruns `nc->maxsp`, which needs a
narrowing tree deeper than the sweep builds. The remainder are
reachable and simply not generated yet.

### Loop mode: outputs are ordered by slot type

`--loop` (and `COV_LOOP`) feeds each generator output back into the
slot its SLOAD reads -- `out[i]` goes to the slot `SLOAD #i` reads --
so `gen.loop_order` permutes the outputs to put a value of that
SLOAD's type at each position. Without it an `int` root lands in a
`num` slot, the two passes model the type change differently, and
the traces disagree over something the optimizer never touched: it
was reporting a signed-zero difference that reduced to
`-2^31 * -0.0` on one side against a symbolic num chain on the
other.

The same order drives the comparison, and that is not incidental:
`attach_snapshot` pairs compared output `i` with slot `i`, so
handing the replay a different order than the compared one models a
slot mapping the replay never performed. A slot with no root of its
type is fed its own SLOAD, which makes it invariant; that is about
1% of slots.

### Known limitation

`--tables` with repeated or dead stores to an *escaping* (SLOAD'd)
table can produce a spurious `sat` from ljopt's memory-diff encoding
(the final-version comparison over the shared memory array), not from a
real optimizer bug. This is an ljopt modelling gap, not a LuaJIT
miscompile; narrowing generation or extending the memory-diff is
tracked as follow-up work.
