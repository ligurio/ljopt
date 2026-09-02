# LuaJIT miscompile at default -O3: hash store lost inside a loop

## Summary

A `t.ka = i` store inside an inner loop is dropped from the compiled
loop body. A read of `t.ka` in the next iteration therefore returns a
stale value, and the value written to `t[2]` is wrong from roughly the
20th outer iteration onward.

This happens at **default `-O3`**. `-O2` and the interpreter are
correct. All values are exact integers, so this is not rounding.

## One-liner

```sh
CODE='local t={ka=0} local s=0 for i=1,400 do for j=1,5 do s=bit.band(t.ka,65535) t.ka=i end end print(s)'

luajit -joff -e "$CODE"     # 400   correct
luajit -O2   -e "$CODE"     # 400   correct
luajit -O3   -e "$CODE"     # 100   WRONG
```

At the end of outer iteration `i` the store `t.ka = i` has run, so
`s = band(t.ka,65535)` must be `i`. For `i = 400` that is `400`.
`-O3` prints `100`.

`t.ka` itself ends up correct; only the value observed by the read
inside the compiled loop is stale.

## Essential ingredients

Established by reduction from a 47-line generated program, and
confirmed against a second independent generated program (seed 100802)
that reduced to the same shape:

| variation | reproduces |
|---|---|
| `bit.band(t.ka, 65535)` | yes |
| `bit.bor(t.ka, 0)` | yes |
| `bit.tobit(t.ka)` | yes |
| plain `t.ka` | **no** |
| `math.floor(t.ka)` | **no** |
| nested loop | required (a single loop does not reproduce) |
| store to a second key | not needed |
| string key `t.ka` vs integer key `t[3]` | both |

So the trigger is a **`bit.*` operation** (all of which lower to IR
`TOBIT`) applied to a table field that is stored later in the same
inner loop body. Neither allocation sinking nor a second table key is
involved -- both were removed without losing the failure.

## It is a lost store, not arithmetic

Logging `t[2]` at the end of each outer iteration:

```
i        1   2   3   20  21  25  50  99  100 200 400
-joff    6   7   8   25  26  30  55  104 105 205 405
-O3      6   7   8   10  10  11  17  30  30  55  105
```

Correct is `i + 5`. Under `-O3` the value tracks roughly `i/4 + 5`, as
if the store only lands on about every fourth outer iteration. The two
agree until `i = 20`, which is when the trace is installed.

## Flag bisection

```
-O3            105   WRONG
-O3,-fwd       405   correct
-O3,-dse       405   correct
-O3,-cse       405   correct
-O3,-fold      405   correct
-O3,-loop      405   correct
-O3,-narrow    105   WRONG
-O3,-sink      105   WRONG
-O3,-abc       105   WRONG
-O3,-fuse      105   WRONG
-O3,-dce       105   WRONG
-O2            405   correct
```

So it needs fwd + dse + cse + fold + loop together. Disabling any one
of those five hides it; narrow/sink/abc/fuse/dce are irrelevant.

## IR

`luajit -O3 -jdump=i` on the reproducer:

```
0014 >  tab SLOAD  #1    T
0018 >  p32 HREFK  0017  "ka" @0
0019 >  num HLOAD  0018            <- read t.ka
0021    int TOBIT  0019  bias
0022    int BAND   0021  +65535
0023 >  int ADDOV  0022  0001
0026 >  p32 HREFK  0017  +2   @1
0029    num CONV   0023  num.int
0030    num HSTORE 0026  0029      <- t[2] = ...
0031 >  num SLOAD  #5    T         <- i
0032    num HSTORE 0018  0031      <- t.ka = i   (PRE-LOOP ONLY)
0033  + int ADD    0001  +1
0034 >  int LE     0033  +5
0035 ------ LOOP ------------
0036    int TOBIT  0031  bias      <- reads the forwarded 0031, no reload
0037    int BAND   0036  +65535
0038 >  int ADDOV  0037  0033
0039    num CONV   0038  num.int
0040    num HSTORE 0026  0039      <- t[2] = ...
0041  + int ADD    0033  +1
0042 >  int LE     0041  +5
0043    int PHI    0033  0041
```

The loop body (0036-0043) contains **no `HSTORE` to ref 0018**, i.e.
`t.ka = i` is absent from the compiled loop. The store survives only in
the pre-loop section at `0032`. Correspondingly `0036` consumes the
forwarded value `0031` rather than reloading `t.ka`.

Within a single execution of the inner loop that is self-consistent --
`i` does not change across `j`, so re-storing the same value is
redundant and forwarding the load is valid. The defect shows up across
re-entries of the trace, when `i` has advanced but the loop body still
neither re-stores `t.ka` nor reloads it.

## Scope

Reproduces identically (`105 400`) on all 9 LuaJIT builds available
here -- tarantool/luajit af5d38f1, b52fe979, 203a9868, ab0c0793,
c9588f51, plus the local cov/inject/buggy builds -- and on the system
`luajit`. Unlike the sibling `-O-dce` finding, the wrong value is
identical everywhere, so this is deterministic rather than a read of
stale register state.

Minimal ingredients, established by reduction from a 47-line generated
program:

- a nested loop; the inner one is what gets compiled
- a hash read of `t.ka` feeding `bit.band` (the int/num CONV matters --
  replacing `bit.band(t.ka,65535)` with plain `t.ka` does not reproduce)
- a store to a different key of the same table (`t[2]`)
- a store back to `t.ka` in the same iteration

The conditional guard and both table constructors present in the
original generated program were removed without losing the failure, so
allocation sinking is not involved.

## How it was found

Differential fuzzing: generated integer-only Lua programs (all values
kept exact under a modulus) run under `-joff` and 14 JIT
configurations, comparing stdout; then line-level delta debugging and
hand reduction. Found as seed 72464 of the exact-arithmetic generator.
