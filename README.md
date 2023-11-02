## Translate LuaJIT BC and IR to SMT-LIB

is an implementation of translation validation for LuaJIT.

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
$ tarantool bin/ljopt "$(example.lua)" > example.smt2
```

Validate correctness of the `fold` optimisation with SMT solver, for example
Z3:

```sh
$ z3 -smt2 example.smt2
```

### License

The MIT License, see LICENSE.
