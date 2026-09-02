# LuaJIT miscompile: loop-invariant snapshot value clobbered when DCE is off

## Summary

With `-O-dce`, a loop-invariant value that is referenced **only** by
snapshots taken after the `LOOP` marker gets a register that the loop
body later reuses. On the side exit, the snapshot restores that slot
from the clobbered register, so an unrelated variable's value is
written into it.

The result is not "slightly off" -- the restored variable takes on the
value of a different live variable, and any arithmetic built on it
diverges without limit.

## Reproducer

```lua
local t2 = {}
local x, y, n = 1, 2, 0
for i = 1, 400 do
  for j = 1, 5 do
    y = #t2 * 1
    local s2 = { 0, 0 }
    n = n + s2[1] - s2[2]
  end
  n = n + x + y
end
print(string.format("%.17g", n))   -- expect 400
```

`t2` is empty, so `#t2 == 0` and `y` must be `0` on every iteration.
`s2` is `{0, 0}`, so the inner loop adds nothing. Expected output is
exactly `400`.

```
luajit -joff     -> 400                      correct
luajit -O3       -> 400                      correct
luajit -O3,-dce  -> 1.513037037941548e+118   WRONG
```

## It is not arithmetic

The wrong value is independent of every constant in the program:

| `s2` contents | expected | `-O3,-dce` |
|---|---|---|
| `{0, 1e10}` | -19999999999600 | -4.0978086443493709e+128 |
| `{0, 1}`    | -1600           | -3.34129012545425e+118   |
| `{0, 2}`    | -3600           | -7.4390987698792723e+118 |
| `{1, 1}`    | 400             | 1.513037037941548e+118   |
| `{0, 0}`    | 400             | 1.513037037941548e+118   |

With `{0, 0}` no large number appears anywhere in the program, yet the
result is ~1.5e118. `0x1.8p+392` is 1.5 x 2^392 -- repeated doubling,
not rounding.

## What actually happens

Printing `y` and `n` each iteration under `-O3,-dce`:

```
i=  1  y=0    n=1
...
i= 11  y=0    n=11
i= 12  y=11   n=23      <-- y takes the previous value of n
i=400  y=7.56518518970774e+117  n=1.513037037941548e+118
```

At `i=12`, when the trace is installed, `y` stops being `0` and becomes
the previous value of `n`. From then on
`n = n + x + y` is `n + 1 + n = 2n + 1`, so `n` doubles every
iteration and ends near 2^392.

## Root cause

IR for trace 1 under `-O3,-dce` (`-jdump=isr`, register column kept):

```
0003 [10]     int CALLL  lj_tab_len  (0002)
0004 xmm7     num CONV   0003  num.int        <- y's value, dead in IR
0008 xmm7  >  num SLOAD  #4    T              <- n
0009 [8]    + num ADD    0008  +0
....          SNAP #1  [ ---- ---- ---- 0004 0009 ... ]
....          SNAP #2  [ ---- ---- ---- 0004 0009 ... ]
0013 ------------ LOOP ------------
0017 xmm7   + num ADD    0009  +0
....          SNAP #3  [ ---- ---- ---- 0004 0017 ... ]
0022 xmm7     num PHI    0009  0017
```

Ref `0004` holds `y`. It is defined **before** the `LOOP` marker and is
referenced by `SNAP #3`, taken **after** it, so it must stay live across
the whole loop. But `0004` has no other use in the IR -- it is dead
except for snapshots.

`asm_snap_alloc1()` (lj_asm.c) gives such a ref a register and then
marks it *weak*:

```c
Reg r = ra_allocref(as, ref, allow);   /* Allocate a register. */
if (!irt_isphi(ir->t))
  ra_weak(as, r);                      /* But mark it as weakly referenced. */
```

A weak register may be taken without spilling. `0004` is not a PHI, so
it is weak; the loop body then allocates the same `xmm7` for the `n`
PHI chain (`0008` / `0017` / `0022`). At the side exit, SNAP #3 restores
slot 3 from `xmm7`, which by then holds `n`.

`ra_allocref()` does try to avoid this -- line ~641 prefers registers
outside `as->modset` for refs below `as->loopref` -- but it is only a
preference, and here it does not hold.

## Why DCE hides it

`lj_opt_dce()` runs immediately before `lj_opt_loop()`
(lj_trace.c:706-707). With DCE on, the dead `CONV` at `0004` is removed
and the snapshot instead references the int `0003`, which has a real
spill slot `[10]` and survives. With DCE off the dead `CONV` stays and
inherits the fragile weak register.

So DCE is not the buggy pass; it merely removes the instruction that
exposes the allocator's assumption.

## Scope

Reproduces on all 9 LuaJIT builds available here (including
tarantool/luajit at af5d38f1, b52fe979, 203a9868, ab0c0793, c9588f51)
and on the system `luajit`. The wrong value differs between builds
(-4.09e128 vs -8.19e128), consistent with reading whatever register
state happens to be live.

Not reachable at any default level: `-O1`, `-O2` and `-O3` are all
correct. `-O-dce` is a documented tunable, so a wrong result there is
still a defect, but user impact is limited.

Flag bisection:

```
-O3,-dce            wrong
-O3,-dce,-sink      wrong    (not allocation sinking)
-O3,-dce,-fwd       correct  (needs store forwarding)
-O3,-dce,-loop      correct  (needs the loop pass)
```

## Fix

Not found. One candidate was tried and rejected: forcing a spill in
`asm_snap_alloc1()` when a loop-invariant snapshot ref lands in a
register present in `as->modset`

```c
if (as->loopref && ref < as->loopref && rset_test(as->modset, r))
  ra_spill(as, ir);
else if (!irt_isphi(ir->t))
  ra_weak(as, r);
```

This did **not** fix the reproducer, so either the register is assigned
on a different path than the one patched, or `modset` is not yet
populated at that point in the backward walk. The precise liveness rule
for "loop-invariant, snapshot-only, referenced after LOOP" still needs
to come from someone who knows the allocator.

## How it was found

Differential fuzzing: generated Lua programs run under `-joff` and under
13 JIT configurations, comparing stdout. Reduced with a line-level delta
debugger. It was **not** found by ljopt -- see below.

## Note for ljopt

ljopt returns `unsat` (equivalent) on this program. That is correct
behaviour, not an ljopt bug: the IR is semantically fine, and the defect
is introduced by register allocation in the assembler backend. ljopt
translates IR to SMT and stops there, so backend bugs of this class are
structurally outside what it can see.
