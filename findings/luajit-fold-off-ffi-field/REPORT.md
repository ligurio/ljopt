# LuaJIT miscompile with -Ofold disabled: FFI struct field, still open

## Summary

A 39-line generated program prints `164` in the interpreter and at
default `-O3`, but `165` with `-Ofold` switched off.

```
luajit -joff              repro.lua   # 164 ...   correct
luajit -O3                repro.lua   # 164 ...   correct
luajit -Ohotloop=1,-fold  repro.lua   # 165 ...   WRONG
luajit -O3,-fold          repro.lua   # 165 ...   WRONG
```

The printed `acc` is `p.x + q.n + v.v` with `q.n` always 0, so the
difference is one unit in `v.v`: the JIT runs `v:bump()` on an
iteration where the interpreter does not. `v:bump` is reached only
under `219 < (p.x*31 + 1) % 1000003`, and `p.x` is set to 1 earlier
in the same iteration, which makes that test false. Taking the branch
means the compiled trace evaluated the condition against a `p.x` the
current iteration had already overwritten.

## Distinct from luajit-tobit-clobbers-invariant

This reproduces on a build carrying that fix
(`findings/luajit-tobit-clobbers-invariant/fix.patch`), so it is a
different defect. Worth stating because the previous fold-off
finding, `findings/luajit-fold-off-wrong-table`, turned out to be
the TOBIT bug and no longer reproduces once that patch is applied --
see the note in its report.

## Flag fingerprint

    levels = [ -Ohotloop=1,-fold  -O3,-fold ]
    needs  = [ narrow  loop  fuse ]

Turning any one of `narrow`, `loop` or `fuse` back on hides it.
Default `-O3` is correct, so this is not a default-level miscompile;
`-fold` is a documented `-O` sub-flag, so the combination is
supported.

## Reproduces on

All nine LuaJIT builds in `build/`, plus the system `luajit`. The
result is identical everywhere: `164` interpreted, `165` with
folding off.

## Localization

Measured on the reduced reproducer:

| variation | result |
|---|---|
| `-Ohotloop=1,-fold` | wrong (165) |
| `+ hotexit=1000000` (no side traces compiled) | **wrong** |
| `+ maxside=0` | **wrong** |
| `+ -abc` | wrong |
| `+ -fuse` | correct |
| `+ maxsnap=1` | correct |

So the defect is in the **root trace**, not in a side trace or an
exit taken into one. Backend operand fusion is required.

What is *not* the mechanism: the IR keeps the right order in the
loop body -- `XSTORE &p.x, 1` (0139), then `XLOAD &p.x` (0159), then
the guard (0168), then `XSTORE &p.x, 164` (0183) -- and the machine
code preserves it, with the store and the fused reload using the
same base and displacement:

```
mov     dword [r12+0x8], 0x1        ; p.x = 1
...
cvtsi2sd xmm7, dword [r12+0x8]      ; reload, fused into the convert
```

A stale load across the store is therefore ruled out at both levels;
the mechanism is still unknown.

## Reduction

Reduced from 76 lines to 39 by line deletion and then by source
transformation. It does not reduce further: the branches that look
dead (`if 1 < 1 then end`, `if (i) < (1) then ... end`) are
load-bearing -- deleting any of them makes the divergence disappear,
so the bug depends on the shape of the recorded trace rather than on
the data flow alone. A hand-written minimal version of the suspected
mechanism (store to `p.x`, reload, compare) does **not** reproduce.

## Provenance

Differential fuzzing (`ljopt/diffuzz`), FFI generator, seed 4001698.

Not a new sighting. The same bug had been reported by the FFI
generator since the first sweep of the day -- seeds 320577, 322542,
323769 and 327523 all still diverge on a build carrying the TOBIT
fix, so they were never that bug. They were being auto-labelled
`[known]` against a fingerprint whose note pointed at
`luajit-fold-off-wrong-table`, which is a *different* defect, so
they were dismissed for most of the day. This report is the first
time the bug has its own reproducer.
