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

5. **`fuzz.lua` — drive.** Runs z3 on each query (standalone binary, so
   one crash/timeout can't sink the run) and reports every `sat` with
   its seed.

The optimized and un-optimized traces run through identical translation,
so if they diverge in the SMT it is because the optimizer changed an
observable value: `unsat` ⇒ the optimizer preserved observable state,
`sat` ⇒ a candidate miscompile (or an ljopt modelling gap — triage by
`--show`).

## Usage

Needs z3 on `LD_LIBRARY_PATH` (see repo `CLAUDE.md`: `../z3/build`) and
the luajit fork with the irfuzz patch applied (the `make`-built
`build/luajit_<tag>` already has it).

```sh
# One seed: dump both IR traces and the full SMT query.
luajit ljopt/irfuzz/fuzz.lua --show 17

# Sweep: check N seeds starting at S; prints SAT <seed> for candidates.
luajit ljopt/irfuzz/fuzz.lua --seed 1 --count 5000

# Also generate table/array memory ops (AREF/HREF/ALOAD/HLOAD/…).
luajit ljopt/irfuzz/fuzz.lua --tables --seed 1 --count 2000

# Also generate ops ljopt models incompletely, to hunt ljopt gaps
# rather than LuaJIT miscompiles.
luajit ljopt/irfuzz/fuzz.lua --include-gaps --seed 1 --count 2000
```

Flags: `--seed S`, `--count N`, `--insns K` (body length), `--no-ints`
(num only), `--include-gaps`, `--tables`, `--show SEED`.

Tuning env vars: `LJOPT_Z3_BIN` (default `../z3/build/z3`),
`LJOPT_Z3_TIMEOUT` (seconds, default 15).

Every seed is a pure function of its number, so any `SAT seed=N`
reproduces exactly with `--show N`.

## Instruction coverage

- **Arithmetic** — binary num (`ADD SUB MUL DIV MOD POW MIN MAX`), int
  (`ADD SUB MUL DIV MOD`, `BAND BOR BXOR`, shifts, rotates); unary num
  `NEG`/`ABS`, unary int `NEG`/`BNOT`/`BSWAP`; `FPMATH` rounding modes
  and `LDEXP`.
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
