## LuaJIT BC to SMT

### Example

```
$ luajit -jdump=-m -O+loop -Ohotloop=1 -e 'local b; for i = 1, 3 do b = 20 end'
---- TRACE 1 start (command line):1
0006  KSHORT   0  20
0007  FORL     1 => 0006
---- TRACE 1 IR
0001    int SLOAD  #2    CI
0002  + int ADD    0001  +1
0003 >  int LE     0002  +3
0004 ------ LOOP ------------
0005  + int ADD    0002  +1
0006 >  int LE     0005  +3
0007    int PHI    0002  0005
---- TRACE 1 stop -> loop

$ luajit -bl -e "local a = 10; for i = 1, 20 do a = 30 end"
-- BYTECODE -- 0x4034a150:0-1
0001    KSHORT   0  10
0002    KSHORT   1   1
0003    KSHORT   2  20
0004    KSHORT   3   1
0005    FORI     1 => 0008
0006 => KSHORT   0  30
0007    FORL     1 => 0006
0008 => RET0     0   1
$
```

### Parse LuaJIT bytecode

1. `string.dump(f [, strip])`, Lua API, compatible with LuaJIT as well as PUC Rio Lua.

> Returns a string containing a binary representation of the given function, so
> that a later loadstring on this string returns a copy of the function. `function`
> must be a Lua function without upvalues.

Example:

```lua
tarantool> string.dump(function() print() end)
---
- "\eLJ\x02\0*return string.dump(function() print() end) \0\0\x01\0\x01\0\x03\x04\x01\06\0\0\0B\0\x01\x01K\0\x01\0\nprint\0\0\0\0\0"
...

tarantool>
```

### References

- LuaJIT Wiki: The LuaJIT 2.0 Bytecodes, https://github.com/tarantool/tarantool/wiki/LuaJIT-Bytecodes
- Bytecode parsers:
  - bytecode parser in python https://gist.github.com/MickaelWalter/4b130d36040844abcb71bf69fe8d6fd4?ref=mickaelwalter.fr
  - annotate.lua https://github.com/geoffleyland/luatrace/blob/master/lua/jit/annotate.lua
  - (!) Lua: https://github.com/franko/luajit-lang-toolkit/blob/master/lang/bcread.lua
  - (!) Lua: LuaJIT 2.1 Bytecode Parser https://github.com/imring/DisLua
  - C: lbci, A Lua bytecode inspector library, https://github.com/LuaDist/lbci
  - ldumplib, A bytecode dumper for Lua 4.0 http://webserver2.tecgraf.puc-rio.br/~lhf/ftp/lua/
  - https://github.com/franko/luajit-lang-toolkit
  - C: https://github.com/sztupy/luadec51/tree/master/luadec
  - Lua: https://gist.github.com/meepen/807dd81a572ffb0f28a8c44c04922fdd
  - Python: https://gitlab.com/znixian/luajit-decompiler
  - C: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_bcread.c
  - Python: https://github.com/luavela/dumpanalyze
- `jit.dump` source code, https://github.com/LuaJIT/LuaJIT/blob/master/src/jit/dump.lua
- `string.dump` description, https://luajit.org/extensions.html#string_dump
- "A no-frills introduction to Lua 5 VM instructions.",
  http://underpop.free.fr/l/lua/docs/a-no-frills-introduction-to-lua-5.1-vm-instructions.pdf
- "The Implementation of Lua 5.0", https://www.lua.org/doc/jucs05.pdf
- "Optimizing Lua VM Bytecode using Global Dataflow Analysis" (Chapter 3 Optimizing),
  https://nymphium.github.io/pdf/opeth_report.pdf
- "Technical Documentation trace-based just-in-time compiler LuaJIT" (4.3 Optimisation),
  https://raw.githubusercontent.com/MethodicalAcceleratorDesign/MADdocs/master/luajit/luajit-doc.pdf
- [LuaJIT bytecode listing module](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/jit/bc.lua)
- Tarantool documentation: https://www.tarantool.io/en/doc/latest/reference/reference_lua/jit/#jit-bc-dump

2. `require("jit.bc").dump(f)`, LuaJIT-specific.

Example:

```lua
local bc = require("jit.bc")

local function foo() print("hello") end

bc.dump(foo)           --> -- BYTECODE -- [...]
print(bc.line(foo, 2)) --> 0002    KSTR     1   1      ; "hello"
```

```
tarantool> jit_bc = require('jit.bc')
---
...

tarantool> function f()
         > print("D")
         > end
---
...

tarantool> jit_bc.dump(f)
-- BYTECODE -- 0x01113163c8:1-3
0001    GGET     0   0      ; "print"
0002    KSTR     2   1      ; "D"
0003    CALL     0   1   2
0004    RET0     0   1

---
...
```

## LuaJIT IR to SMT

`git effort`:

```
  src/lj_asm.c.................. 248         165
  src/lj_record.c............... 219         145
  src/lj_crecord.c.............. 155         110
  src/lj_opt_fold.c............. 147         98    <-------- o_O
  src/lj_arch.h................. 132         103
  src/lj_asm_x86.h.............. 109         77
  src/lj_err.c.................. 106         89
  src/lj_trace.c................ 101         78
  ...
```

```sh
diff -u <(luajit -O-dse -jdump=i trash/opt-tests/dse/array.lua) <(luajit -O+dse -jdump=i trash/opt-tests/dse/array.lua)
diff -u <(luajit -O-dse -jdump=i trash/opt-tests/dse/field.lua) <(luajit -O+dse -jdump=i trash/opt-tests/dse/field.lua)
diff -u <(luajit -O-fwd -jdump=i trash/opt-tests/fwd/tnew_tdup.lua) <(luajit -O+fwd -jdump=i trash/opt-tests/fwd/tnew_tdup.lua)
diff -u <(luajit -O-fold -jdump=i trash/opt-tests/fold/kfold.lua) <(luajit -O+fold -jdump=i trash/opt-tests/fold/kfold.lua)
```

----

3. `jit.attach()`

- https://wiki.facepunch.com/gmod/jit.attach
- https://luajit.org/ext_jit.html

Attach a handler to the compiler pipeline with the given priority. The handler
is detached if no priority is given. The inner workings of the compiler
pipeline and the API for handlers are still in flux. Please see the source code
for more details.

You can attach callbacks to a number of compiler events with `jit.attach`.
The callback can be called:

- when a function has been compiled to bytecode ("bc");
- when trace recording starts or stops ("trace");
- as a trace is being recorded ("record");
- or when a trace exits through a side exit ("texit").

Set a callback with `jit.attach(callback, "event")` and clear the same callback
with `jit.attach(callback)`.

**Arguments**

1. function `callback`

The callback function.

The arguments passed to the callback depend on the event being reported:

- "bc": function func - The function that's just been recorded
- "trace": string what - description of the trace event: "flush", "start",
  "stop", "abort". Available for all events.
- number tr - The trace number. Not available for flush.
- function func - The function being traced. Available for start and abort.
- number pc - The program counter - the bytecode number of the function being
  recorded (if this a Lua function). Available for start and abort.
- number otr - start: the parent trace number if this is a side trace, abort: abort code
- string oex - start: the exit number for the parent trace, abort: abort reason (string)
  "record": number tr - The trace number. Not available for flush.
- function func - The function being traced. Available for start and abort.
- number pc - The program counter - the bytecode number of the function being
  recorded (if this a Lua function). Available for start and abort.
- number depth - The depth of the inlining of the current bytecode.
  "texit": number tr - The trace number. Not available for flush.
- number ex - The exit number
- number ngpr - The number of general-purpose and floating point registers that
  are active at the exit.
- number nfpr - The number of general-purpose and floating point registers that
  are active at the exit.

2 string event

The event to hook into.

#### References

- LuaJIT Wiki: LuaJIT SSA IR, https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR
- LuaJIT Wiki: Not Yet Implemented, https://github.com/tarantool/tarantool/wiki/LuaJIT-Not-Yet-Implemented
- Running LuaJIT, https://luajit.org/running.html#opt_b
- [LuaJIT compiler dump module](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/jit/dump.lua)
- LuaJIT Wiki: LuaJIT Optimizations, https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations
- LuaJIT Wiki: LuaJIT Allocation Sinking Optimization, https://github.com/tarantool/tarantool/wiki/LuaJIT-Allocation-Sinking-Optimization
- LuaJIT tests on optimisations, https://github.com/tarantool/luajit/tree/tarantool/test/LuaJIT-tests/opt
- `fold` - Constant Folding, Simplifications and Reassociation
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_fold.c
  - https://github.com/LuaJIT/LuaJIT/issues/299
  - https://github.com/LuaJIT/LuaJIT/issues/1084
  - https://github.com/LuaJIT/LuaJIT/issues/1079
  - https://github.com/LuaJIT/LuaJIT/issues/981
  - https://github.com/LuaJIT/LuaJIT/issues/833
  - https://github.com/LuaJIT/LuaJIT/issues/799
  - https://github.com/LuaJIT/LuaJIT/issues/797
  - https://github.com/LuaJIT/LuaJIT/issues/792
  - https://github.com/LuaJIT/LuaJIT/issues/505
  - https://github.com/LuaJIT/LuaJIT/issues/540
  - https://github.com/LuaJIT/LuaJIT/issues/311
  - https://github.com/LuaJIT/LuaJIT/issues/311
  - "Tutorial: How Folding Engine Works"
    https://ujit.readthedocs.io/en/latest/public/tut-folding-engine.html
- `cse` - Common-Subexpression Elimination
  - https://github.com/LuaJIT/LuaJIT/issues/1086
  - https://github.com/LuaJIT/LuaJIT/issues/1084
- `dce` - Dead-Code Elimination
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_dce.c
  - https://github.com/LuaJIT/LuaJIT/issues/791
  - https://github.com/LuaJIT/LuaJIT/issues/651
  - https://github.com/LuaJIT/LuaJIT/issues/1094
- `narrow` - Narrowing of numbers to integers
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_narrow.c
  - https://github.com/LuaJIT/LuaJIT/issues/858
- `loop` - Loop Optimizations (code hoisting)
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_loop.c
- `fwd` - Load Forwarding (L2L) and Store Forwarding (S2L)
  - https://github.com/LuaJIT/LuaJIT/issues/606
- `dse` - Dead-Store Elimination
- `abc` - Array Bounds Check Elimination
  - https://github.com/LuaJIT/LuaJIT/issues/794
- `sink` - Allocation/Store Sinking
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_sink.c
- `fuse` - Fusion of operands into instructions
- `fma` - Fused multiply-add
- "Memory access optimizations",
  https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_mem.c
- "SPLIT: Split 64 bit IR instructions into 32 bit IR instructions",
  https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_split.c

## Проекты для проверки эквивалентности кода для тестирования оптимизаций

- libfuzzer + solidity https://blog.soliditylang.org/2021/02/10/an-introduction-to-soliditys-fuzz-testing-approach/
- Solidity https://github.com/ethereum/solidity/tree/develop/test/formal
- https://github.com/boogie-org/boogie
- https://github.com/p4gauntlet/gauntlet
- https://www.usenix.org/conference/osdi20/presentation/ruffy
- Alive2 для проверки оптимизаций https://web.ist.utl.pt/nuno.lopes/pubs.php?id=alive2-pldi21
- https://foss.heptapod.net/pypy/pypy/-/issues/3832
- Alive2 https://github.com/MattPD/cpplinks/blob/master/compilers.correctness.md#verification
> You can use Z3 to encode the source code before and after a compiler
> optimization as a logic formula and then check whether the formulae are
> equivalent. If they are not, there is likely a semantic bug in the
> transformation pass of your compiler, meaning you have introduced a subtle
> logic mistake.
- Z3 и SQL https://cosette.cs.washington.edu/
- https://github.com/SRI-CSL/llvm2smt#what-we-do
- PyPy https://www.pypy.org/posts/2022/12/jit-bug-finding-smt-fuzzing.html
- https://kristerw.github.io/2022/11/01/verifying-optimizations/
- https://github.com/kristerw/pysmtgcc/blob/main/smtgcc.py

## Трансляция в SMT-LIB

- http://www.cprover.org/cprover-manual/cbmc/unwinding/
- https://github.com/SRI-CSL/llvm2smt#what-we-do
- https://www.pypy.org/posts/2022/12/jit-bug-finding-smt-fuzzing.html
- https://kristerw.github.io/2022/09/13/translation-validation/
- https://symflower.com/en/company/blog/2021/40-year-old-riddle-solved/
- https://symflower.com/en/company/blog/2021/it-is-simply-math/
- https://symflower.com/en/company/blog/2021/ssa/
- An Abstract Interpretation-based Model of Tracing Just-In-Time
Compilation, https://arxiv.org/pdf/1411.7839.pdf
