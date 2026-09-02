## IR-optimizer fuzzer for ljopt

Adds a deterministic, seed-driven fuzzer that stress-tests LuaJIT's
trace optimizer (the FOLD engine + load/store forwarding) through
ljopt's own SMT equivalence oracle, plus the one ljopt modelling fix
the initial sweep surfaced.

See `ljopt/irfuzz/README.md` for the full design.

### Pipeline

```
seed → gen.lua → jit.util.irfuzz (replay through FOLD at -O0 and -O3)
     → decode.lua → check.lua → ir_smtlib.compare_trace_records → z3
```

`unsat` ⇒ the optimizer preserved observable state; `sat` ⇒ a candidate
miscompile (or an ljopt modelling gap, classified out via
`get_nyi_nodes` / `UNINTERPRETED`). Every seed reproduces exactly with
`--show N`.

### Commits

- **model MIN/MAX with ordered min/max** — the one bug the sweep found:
  ljopt emitted SMT `fp.min`/`fp.max`, which are unspecified on ±0, so a
  folded `MIN(-0.0, +0.0)` → `+0.0` looked inequivalent to the un-folded
  `num MIN`. Now modelled as `(ite (fp.lt a b) a b)`, matching
  `lj_vm_foldarith`. Fixed seeds 17/180/339/636.
- **expose `compare_trace_records`** — split from `traces_to_smt` so the
  fuzzer reuses the exact recorded-path oracle (no behavior change).
- **fuzzer harness + arithmetic coverage** — `irfuzz/{gen,decode,check,fuzz}.lua`
  + the `jit.util.irfuzz` luajit patch. Blacklist-based op selection
  (RECORDER_IMPOSSIBLE vs KNOWN_LJOPT_GAP). Covers binary/unary num & int
  arith, bitwise, shifts, FPMATH, LDEXP.
- **table/array coverage (`--tables`)** — SLOAD tab, FLOAD tab.array,
  AREF/HREF, ALOAD/HLOAD, ASTORE/HSTORE. Array vs hash keys kept in
  disjoint ranges to match LuaJIT's separate array/hash address spaces.
- **README** + line-length cleanup.

### Results

- Arithmetic: swept seeds 1..5000, **0 sat** after the MIN/MAX fix.
- Tables: swept seeds 1..1600, ~99.8% unsat. Two seeds (358, 1154) hit a
  **known ljopt memory-diff limitation** on repeated/dead stores to an
  escaping table (an ljopt modelling gap, not a LuaJIT miscompile) —
  documented in the README as follow-up.

### Testing

- `tests/tests.lua`, `ir_tests.lua`, `unit_tests.lua` pass with the
  MIN/MAX change.
- Needs z3 on `LD_LIBRARY_PATH` (`../z3/build`) and the luajit patch
  applied (the `make`-built `build/luajit_<tag>` has it).
