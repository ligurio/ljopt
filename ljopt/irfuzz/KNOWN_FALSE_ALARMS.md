# Known false alarms

Seeds the fuzzer reports as `sat` although LuaJIT is right: the
difference comes from how ljopt models the trace, not from the
optimizer. Check a new `sat` against this list before triaging it.

All seeds below come from the table generator (`gen_table.lua`) in
loop mode with 12 instructions, the setting `.fuzzrun/fuzz100k.lua`
sweeps with. Its `reproduce: --grammar --show` hint builds a
different trace; rebuild the formula the way the sweep does:

```lua
local gt = require("ljopt.irfuzz.gen_table")
local check = require("ljopt.irfuzz.check")
local insns = gt.gen(SEED, { insns = 12, loop = true })
local r = check.build_from(insns, gt.roots(insns), { loop = true }, SEED)
-- r.formula is the query, r.trace_unopt / r.trace_opt the traces
```

A seed only names a trace for the generator it was found with, so
a later change to `gen_table.lua` can make it build something else.

## Open

### UREFO and UREFC on the same upvalue

Seeds 1800331178, 1800342005 (store through UREFO, load through
UREFC).

```
0011 > p32  UREFO  0010  #34     ; upvalue 34 is open
0012 > num  ULOAD  0011          ; snapshot slot 7
0026 > p32  UREFC  0010  #34     ; upvalue 34 is closed
0029   num  USTORE 0026  -0.0
```

`aa_uref` in `lj_opt_mem.c` answers `ALIAS_NO` for two UREFs of a
different type, so the loop optimizer keeps `0012` invariant and
slot 7 holds the first iteration's value. That is sound: an upvalue
is either open or closed, so both guards cannot pass.

ljopt models both guards as always passing and both references as
the same cell `(closure, "uv.34")`. The unoptimized copy then reads
back the `-0.0` stored through the closed reference, and slot 7
differs.

Fix: make "open" one fact per upvalue, shared by both traces, e.g.
`(declare-fun uv_open (Int MemCell) Bool)`, with the UREFO guard
`(uv_open fn key)` and the UREFC guard `(not (uv_open fn key))`.

### Non-finite float to int conversion folded into a PHI

Seeds 1805271398, 1795341937.

```
0026   num  USTORE 0011  -inf
0012 > num  ULOAD  0011          ; next iteration: -inf
0023   int  CONV   0012  int.num ; (int)-inf, undefined in C
0025 > int  ADDOV  0023  +2
0047   int  PHI    0025  -2147483646  ; optimized: folded
```

LuaJIT folds the conversion the way x86 `cvttsd2si` computes it,
`INT_MIN`, and carries `INT_MIN + 2` as a PHI constant. ljopt models
it as `fp.to_sbv`, which SMT-LIB leaves unspecified for infinities,
so the unoptimized side can hold any value. The recorded path
already treats undefined casts as outside the check (ee414b72); the
loop replay reaches one through a folded PHI constant.

TOBIT on an infinity is the same shape but not undefined: the bias
trick LuaJIT uses keeps the low 32 bits of `inf + 2^52 + 2^51`,
which are 0, so `bit.tobit(-inf)` is 0 and the optimizer folds it
to that. ljopt models TOBIT as `fp.to_sbv 64` too, so there it is an
ljopt gap proper (seed 1795341937, slot 10: `BXOR` of two TOBITs of
`-inf`, folded to 0).

## Fixed

- A table read from memory could decode to the id of a table the
  trace allocates, so a dead `TNEW` the optimizer drops changed
  what `tab.asize` read on one side only. Fixed by
  "ljopt: keep tables read from memory apart from fresh ones".
- A snapshot after the PHIs was cloned as if it were inside the loop
  body, one iteration behind. Fixed by "ljopt: clone snapshots with
  their carried values".
- `CONV i64.num` rounded to nearest where LuaJIT truncates like C,
  so every `--narrow` shape converting a fractional sum to i64 read
  as a miscompile (e.g. #772: 96.86 gave 97 against 96). Fixed by
  "ljopt: truncate in the i64.num CONV" (PR #95).
