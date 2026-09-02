# LuaJIT miscompile with -Ofold disabled: a store lands in the table the code never selects

> **SUPERSEDED.** This reproducer no longer diverges once
> `findings/luajit-tobit-clobbers-invariant/fix.patch` is applied: the
> `bit.band(a, 65535)` in the loop records as TOBIT, and the register
> clobber described there is the same root cause. Kept as the second
> witness for that bug. A fold-off miscompile that survives the TOBIT
> fix is tracked separately in `findings/luajit-fold-off-ffi-field`.

## Summary

`u = (a < 64536) and t3 or t1` always selects `t3`, because `a` only
ever holds `1` or `127`. The interpreter therefore never writes `t1`,
and `t1[1]` stays `nil`.

With `-Ofold` switched off, the JIT writes `t1[1]` anyway.

Needs `-O2` or `-O3` as the base level (`loop` is required, so `-O1`
is unaffected). This is **not** a default-level bug: plain `-O3` is
correct. `-fold` is a documented `-O` sub-flag, so the combination is
a supported configuration.

## One-liner

```sh
CODE='local t1,t3={},{} local a,b,c=1,2,3 for i=1,400 do for j=1,4 do for j=1,2 do local u=(a<64536) and t3 or t1 u[1]=(c-((a<b) and b or 0))%1000003 if (((bit.band(a,65535)*31+i)%1000003)<c) then a=127 end end end c=(c*31+1)%1000003 end print(t1[1])'

luajit -joff     -e "$CODE"    # nil      correct
luajit -O3       -e "$CODE"    # nil      correct
luajit -O3,-fold -e "$CODE"    # 825351   WRONG
```

## Reproduces on

System `luajit`, and all nine LuaJIT builds in `build/`, at both
`-O3,-fold` and `-O2,-fold`. `-O1,-fold` is correct.

## Flag fingerprint

Switching any one of these back on makes it go away:

    cse  narrow  loop

`dce`, `abc`, `sink`, `fuse`, `fwd`, `dse` are irrelevant. This
fingerprint is distinct from `luajit-o3-lost-hstore`
(`fold cse loop fwd dse`), so it is a different bug.

## Mechanism

In the root trace the selection compiles to a guard on two constants:

    0004    num CONV   +64536  num.int
    0051    num CONV   +127    num.int
    0085 ------ LOOP ------------
    0086 >  num LT     0051  0004        ; 127.0 < 64536.0 -- always true

With folding on, `0086` is folded away and the exit does not exist.
With folding off the guard survives into the loop body, and its exit
is taken at run time even though the comparison cannot be false. The
side trace hanging off it records the `else` arm:

    ---- TRACE 2 start 1/17 foldbug.lua:6
    0002 >  tab SLOAD  #1    T           ; t1, the arm never selected
    ...
    0020    num ASTORE 0017  0013        ; writes t1[1]

Slot `#1` is `t1` and slot `#2` is `t3`; the root trace only ever
touches `#2`, which is correct. The wrong store comes entirely from
the side trace behind an exit that should be unreachable.

Both operands of `0086` are loop-invariant values defined before the
`LOOP` marker, which puts the suspicion on what happens to them
across the loop boundary rather than on the comparison itself.

## Provenance

Found by differential fuzzing (`ljopt/diffuzz`), seed 220864 of the
integer/table generator. Reduced from 65 lines to 12.

An earlier version of this section claimed six FFI seeds shared the
bug because their flag fingerprints matched. That was wrong: those
seeds still diverge on a build carrying the TOBIT fix while this
reproducer does not, so they are a different defect -- see
`findings/luajit-fold-off-ffi-field`. A matching flag fingerprint
means the same optimizations are needed, not the same root cause.
