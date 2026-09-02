# IR-optimizer fuzzer — status

## Done

1. **Harness** (`ljopt/irfuzz/{gen,decode,check,fuzz}.lua` +
   `jit.util.irfuzz` C patch) — seed → synthetic IR stream → replay
   through FOLD engine twice (-O0/-O3) → decode to `trace_record` →
   `ir_smtlib.compare_trace_records` → z3. Arithmetic (int+num) and
   table/array (`--tables`) coverage. Documented in
   `ljopt/irfuzz/README.md`.

2. **Real bugs found via this harness, already fixed elsewhere**:
   POW modeled uninterpreted (spurious sat on `x^2 -> x*x` fold —
   [[irfuzz-pow-model-gap]]) and shift ops not masking count & 31
   ([[irfuzz-shift-mask-gap]]). Both excluded from the generator via
   a blacklist so the fuzzer now targets remaining gaps, not these
   known ones.

3. **Output selection fixed** (commit `da078d7`): outputs are now the
   *roots* of the generated dataflow (every computed result nothing
   else consumes), not just "last live ref per type" — matches what a
   real snapshot captures and avoids over-constraining CSE/reassoc.

4. **Fold-rule constant pools embedded** (same commit): `NUM_CONSTS`/
   `INT_CONSTS` now carry the exact literals `lj_opt_fold.c` special-
   cases (0/±1/2/0.5 family for num; 0/1/2/4.../masks/shift-boundaries
   for int) instead of arbitrary "interesting" values, so
   constant-guarded folds actually fire during random generation.
   Baseline: seeds 1..60 insns=8 → 45 unsat / 0 sat / 15 unknown
   (z3 timeouts on FP division, not bugs).

## In progress, uncommitted

- `check.lua`: split `build(seed, opts)` into `build_from(insns,
  outputs, opts, seed)` (the shared replay→decode→SMT pipeline) +
  a thin `build(seed, opts)` wrapper that calls `gen.gen` first.
  This lets a second generator feed the same pipeline.
- `gen.lua`: pulled the root-finding logic out into a standalone
  `roots(insns)` and exported it, plus `menu_for`, `op_num`,
  `NUM_CONSTS`/`INT_CONSTS`/etc. — all now importable by other
  generators instead of living only inside `gen()`'s closure.
- `ljopt/irfuzz/enum.lua` (new, untracked): a second, *exhaustive*
  generator alongside the random `gen.lua`. Instead of sampling, it
  walks the full cross product of (op, operand) for a bounded leaf
  set (SLOAD inputs + the embedded fold-rule constants) and a fixed
  chain depth, so every constant-triggered fold in the chosen space
  fires at least once rather than depending on random luck. Exposes
  `iter(opts)` (coroutine yielding `{insns, outputs}`) and `count(opts)`
  (closed-form size, since the space explodes fast — e.g. num
  depth=3, 1 input + 11 consts + 6 ops is ~4.5M). Manually smoke-tested
  end-to-end against `check.build_from` (2 traces built successfully);
  not run as a real sweep yet.

## Where we stopped, and why

Stopped right after wiring `enum.lua` to the shared `check.build_from`
pipeline, **before**:

- adding a driver entry point (`fuzz.lua` only knows `check.build`/
  the random path — there's no `--enum` mode or standalone script that
  drives `enum.iter()` through z3 and reports SAT/UNSAT/gap counts
  the way `run()` does for the random path).
- actually running an enum sweep. `count()` for even modest depth/leaf
  choices is in the hundreds of thousands to millions, so before
  spending z3 time on it we need to pick a tractable slice (small
  depth, maybe fewer leaves, `--tables`-style scoping) and decide
  where to cap it.
- committing: `check.lua`/`gen.lua` refactor + `enum.lua` are all
  uncommitted (`git status`), reflecting that this is a mid-feature
  checkpoint, not a finished increment.

Next step: write the enum driver (mirroring `fuzz.lua`'s `run()`),
pick a bounded (depth, leaf-set) slice that runs in reasonable z3
time, and do a first exhaustive sweep to see if it turns up anything
`gen.lua`'s random sampling missed.
