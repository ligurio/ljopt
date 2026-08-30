# ljopt differential fuzzer

An end-to-end fuzzer that checks LuaJIT against itself: it generates a
random Lua program, runs it interpreted and under several JIT
configurations, and compares stdout. A difference is a JIT miscompile,
with no SMT model in the loop.

This complements `ljopt/irfuzz/`, which builds synthetic IR traces and
uses ljopt's SMT oracle. The two find different things. irfuzz reasons
about IR semantics, so it sees optimizer bugs precisely but is blind to
anything introduced after the IR — register allocation, snapshot
restore, trace linking. diffuzz runs real programs, so it covers the
whole pipeline, at the cost of only telling you *that* something is
wrong.

## Why the generated programs look the way they do

Every value stays an exact integer, kept small by reducing modulo
1000003. That is the whole design constraint, and it exists because
floating point ruins the oracle: an interpreter/JIT difference of one
ULP is usually a legitimate libm difference, not a miscompile, and it
drowns real findings in noise. With integers there is nothing to
argue about — the two runs either agree or the compiler is wrong.

For the same reason the generator emits no bit operations on values
outside int32 and no `math.ldexp` with an out-of-range exponent: both
are undefined in LuaJIT, so a difference there says nothing. An earlier
float-based version of this generator reported 679 "mismatches" over
15k seeds, and every one was undefined behaviour rather than a bug.

The programs are built to exercise the passes that actually go wrong:
nested loops (so traces form and get re-entered), tables read and
written under keys that may or may not alias, values that escape to
snapshots, and a checksum over both the accumulator and the final table
contents so a wrong store cannot cancel out silently.

## Usage

```sh
# one seed
LJ=./build/luajit_<sha>/src/luajit ljopt/diffuzz/diffuzz.sh 72464

# a range, 4 workers
LJ=./build/luajit_<sha>/src/luajit ljopt/diffuzz/run.sh 1 100000 4

# shrink a program that diverged
LJ=./build/luajit_<sha>/src/luajit \
  ljopt/diffuzz/reduce.sh /tmp/diffuzz_72464.lua "-O3" /tmp/min.lua

# just print a generated program
luajit ljopt/diffuzz/gen.lua 72464
```

`diffuzz.sh` prints nothing when the runs agree. On a difference it
prints the seed, the JIT flags that triggered it, and the two outputs.

## Configurations tested

`-O3`, `-O2`, `-O1`, `-Ohotloop=1`, `-Ohotloop=1,hotexit=1`,
`-O3,hotloop=2,hotexit=2`, and single passes disabled on top of a
low hot-counter build: `-fold`, `-narrow`, `-loop`, `-fwd`, `-dse`,
`-abc`, `-sink`, `-cse`, plus `-O3,-dce` and `-O3,-fwd`.

Disabling one pass is not just a bisection aid, it is a bug source in
its own right: a pass being off must never change results, so a
difference under `-O-dce` is as much a defect as one at `-O3`. Once a
seed is flagged, the disabled-pass rows tell you immediately which pass
the failure needs.

## Avoiding false positives

Two guards, both learned the hard way:

- A run that times out is skipped rather than reported. Under parallel
  load a 20s limit fired often enough to bury real findings among
  dozens of fake ones.
- Before reporting, the pair is re-run serially with double the
  timeout. Only a difference that survives that is printed.

The oracle is the interpreter. If the interpreter itself errors or
times out there is no baseline, and the seed is skipped.

## Validating the fuzzer

A fuzzer that reports nothing is indistinguishable from a broken one,
so check it can still catch a bug you introduce on purpose. Patching
`fwd_ahload()` in `lj_opt_mem.c` to treat a may-alias store as a
must-alias one

```c
case ALIAS_MAY:  return store->op2;   /* injected fault */
```

makes this generator flag 15 of the first 60 seeds. An earlier
float-based generator caught the same fault on only 2 of 60, which is
what motivated the exact-integer design.
