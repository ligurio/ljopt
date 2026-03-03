## Translate LuaJIT IR to SMT-LIB

is an implementation of translation validation for LuaJIT.

### Building

```sh
make build
```

### Requirements

- LuaJIT 2.1.1781602682 or later, the commit 8e6520a must be present.
- Z3 >= `4.15.3` is recommended, equivalence of some traces could not be
proved on earlier versions.

### Usage

Create a file with Lua source code:

```sh
$ cat << EOF > example.lua
for i = 1, 100 do local a, b = 23, 11; y = a + b end
EOF
```

Execute LuaJIT with disabled and enabled optimisation `fold`:

```diff
$ diff -u <(luajit -O-fold -jdump=Ti example.lua) <(luajit -O+fold -jdump=Ti example.lua)

--- /dev/fd/63	2023-11-02 19:40:58.479664213 +0300
+++ /dev/fd/62	2023-11-02 19:40:58.479664213 +0300
@@ -1,32 +1,21 @@
 ---- TRACE 1 start example.lua:1
 ---- TRACE 1 IR
 0001    int SLOAD  #1    CI
-0002 >  int ADDOV  +23   +11
-0003    fun SLOAD  #0    R
-0004    tab FLOAD  0003  func.env
-0005    int FLOAD  0004  tab.hmask
-0006 >  int EQ     0005  +63
-0007    p32 FLOAD  0004  tab.node
-0008 >  p32 HREFK  0007  "y"  @35
-0009    tab FLOAD  0004  tab.meta
-0010 >  tab EQ     0009  NULL
-0011    num CONV   0002  num.int
-0012    num HSTORE 0008  0011
-0013    nil TBAR   0004
-0014  + int ADD    0001  +1
-0015 >  int LE     0014  +100
-0016 ------ LOOP ------------
-0017    tab FLOAD  0003  func.env
-0018    int FLOAD  0017  tab.hmask
-0019 >  int EQ     0018  +63
-0020    p32 FLOAD  0017  tab.node
-0021 >  p32 HREFK  0020  "y"  @35
-0022    tab FLOAD  0017  tab.meta
-0023 >  tab EQ     0022  NULL
-0024    num HSTORE 0021  0011
-0025    nil TBAR   0017
-0026  + int ADD    0014  +1
-0027 >  int LE     0026  +100
-0028    int PHI    0014  0026
+0002    fun SLOAD  #0    R
+0003    tab FLOAD  0002  func.env
+0004    int FLOAD  0003  tab.hmask
+0005 >  int EQ     0004  +63
+0006    p32 FLOAD  0003  tab.node
+0007 >  p32 HREFK  0006  "y"  @35
+0008    tab FLOAD  0003  tab.meta
+0009 >  tab EQ     0008  NULL
+0010    num HSTORE 0007  +34
+0011    nil TBAR   0003
+0012  + int ADD    0001  +1
+0013 >  int LE     0012  +100
+0014 ------ LOOP ------------
+0015  + int ADD    0012  +1
+0016 >  int LE     0015  +100
+0017    int PHI    0012  0015
 ---- TRACE 1 stop -> loop
```

Translate IR to SMT-LIB:

```sh
$ LUA_PATH="./?/init.lua;;" bin/ljopt example.lua > example.smt2
```

Validate correctness of the `fold` optimisation with SMT solver,
for example Z3:

```sh
$ z3 -smt2 example.smt2
```

Instead of a file a Lua chunk can be read from STDIN:

```sh
$ LUA_PATH="./?/init.lua;;" bin/ljopt - < example.lua
```

Validate correctness of the `fold` optimisation with an SMT solver
(Z3 or cvc5) automatically:

```sh
$ LUA_PATH="./?/init.lua;;" bin/ljopt --check example.lua
SMT backend: CVC5 1.3.0
    Start  1:  example.lua:1
1/1 Trace #1:  example.lua:1..................................   Passed    0.76 sec

100% traces passed, 0 traces failed out of 1

Total verification time (real) =   0.79 sec
```

Every recorded trace is translated into its own formula and checked
separately. Before a trace is checked a `Start N: <file>:<line>` line
reports where it starts (a trace recorded in a loop is reported at that
loop's line), then its result line follows once the solver returns a
`Passed`, `Failed` or `Timeout` verdict, together with the time the
solver spent on the formula. The lines stream out as the traces are
checked. The summary line gives the share of passed traces (traces with a
`Timeout` verdict are counted separately) and the last line reports the
total wall-clock time of the verification.

The backend is selected with `LJOPT_SMT` (cvc5 by default, falling back to
the other solver). An UNSAT formula means the unoptimised and optimised
traces are equivalent and the verification has passed; a SAT formula (a
counterexample is found) means the verification has failed; an undecided
answer is reported as `Timeout`. The exit code is 0, 3 and 4 for a
`Passed`, `Failed` and `Timeout` result respectively. Without a solver
`--check` prints the SMT-LIB formula to stdout and exits with 4.

### License

The MIT License, see LICENSE.
