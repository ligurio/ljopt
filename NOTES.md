## LuaJIT IR to SMT

### How-to

Setup package dependencies:

```sh
$ apt install -y luajit z3
```

Create an `example.lua`:

```lua
local function add(a, b)
	return a + b
end

local bc = string.dump(add)

local fd = io.open("example.luac", "wb")
fd:write(bc)
fd:close()
```

Run: `luajit example.lua`

Translate `example.luac` to `example.z3`: `luajit lj2smt.lua example.luac`

Execute Z3: `z3 example.z3`

### Exporting BC/IR

<!--
1. `luajit -b -e "local function add(a, b) return a + b end; add(1, 2)" luac.out`
2. `luajit -jdump=bi -O+loop -Ohotloop=1 -e "local function add(a, b) return a + b end; add(1, 4) add(1, 2) add(1, 54)"`
3. `luajit -jdump=bi -O+loop -Ohotloop=1 -e "local b; for i = 1, 3 do b = 20 end"`
4. `string.dump(f [,strip])`
-->

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

<details>
  <summary>Parsing BC/IR</summary>

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

</details>

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

Source code: [LuaJIT bytecode listing module](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/jit/bc.lua)

Tarantool documentation: https://www.tarantool.io/en/doc/latest/reference/reference_lua/jit/#jit-bc-dump

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

Source code: [LuaJIT compiler dump module](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/jit/dump.lua)

### Optimisations

- `fold` - Constant Folding, Simplifications and Reassociation
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_fold.c
  - fold: https://github.com/LuaJIT/LuaJIT/issues/299
  - fold: https://github.com/LuaJIT/LuaJIT/issues/1084
  - fold: https://github.com/LuaJIT/LuaJIT/issues/1079
  - fold?: https://github.com/LuaJIT/LuaJIT/issues/981
  - fold: https://github.com/LuaJIT/LuaJIT/issues/833
  - fold: https://github.com/LuaJIT/LuaJIT/issues/799
  - fold: https://github.com/LuaJIT/LuaJIT/issues/797
  - fold: https://github.com/LuaJIT/LuaJIT/issues/792
  - fold: https://github.com/LuaJIT/LuaJIT/issues/505
  - fold: https://github.com/LuaJIT/LuaJIT/issues/540
  - fold: https://github.com/LuaJIT/LuaJIT/issues/311
  - fold: https://github.com/LuaJIT/LuaJIT/issues/311
  - "Tutorial: How Folding Engine Works"
    https://ujit.readthedocs.io/en/latest/public/tut-folding-engine.html
- `cse` - Common-Subexpression Elimination
  - cse: https://github.com/LuaJIT/LuaJIT/issues/1086
  - cse: https://github.com/LuaJIT/LuaJIT/issues/1084
- `dce` - Dead-Code Elimination
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_dce.c
  - dce: https://github.com/LuaJIT/LuaJIT/issues/791
  - dce: https://github.com/LuaJIT/LuaJIT/issues/651
  - dce: https://github.com/LuaJIT/LuaJIT/issues/1094
- `narrow` - Narrowing of numbers to integers
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_narrow.c
  - narrow: https://github.com/LuaJIT/LuaJIT/issues/858
- `loop` - Loop Optimizations (code hoisting)
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_loop.c
- `fwd` - Load Forwarding (L2L) and Store Forwarding (S2L)
- `dse` - Dead-Store Elimination
- `abc` - Array Bounds Check Elimination
  - abc/fold: https://github.com/LuaJIT/LuaJIT/issues/794
- `sink` - Allocation/Store Sinking
  - Source: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_sink.c
- `fuse` - Fusion of operands into instructions
- `fma` - Fused multiply-add

- "Memory access optimizations",
  https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_mem.c
- "SPLIT: Split 64 bit IR instructions into 32 bit IR instructions",
  https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_split.c

### References

- bytecode parser in python https://gist.github.com/MickaelWalter/4b130d36040844abcb71bf69fe8d6fd4?ref=mickaelwalter.fr
- annotate.lua https://github.com/geoffleyland/luatrace/blob/master/lua/jit/annotate.lua
- `jit.dump` source code, https://github.com/LuaJIT/LuaJIT/blob/master/src/jit/dump.lua
- "Running LuaJIT", https://luajit.org/running.html#opt_b
- `string.dump` description, https://luajit.org/extensions.html#string_dump
- "SSA-IR-2.0", http://web.archive.org/web/20220607041118/http://wiki.luajit.org/SSA-IR-2.0
- "Bytecode-2.0", https://web.archive.org/web/20220717120825/http://wiki.luajit.org/Bytecode-2.0
- "A no-frills introduction to Lua 5 VM instructions.",
  http://underpop.free.fr/l/lua/docs/a-no-frills-introduction-to-lua-5.1-vm-instructions.pdf
- "The Implementation of Lua 5.0", https://www.lua.org/doc/jucs05.pdf
- "Optimizing Lua VM Bytecode using Global Dataflow Analysis" (Chapter 3 Optimizing),
  https://nymphium.github.io/pdf/opeth_report.pdf
- "Technical Documentation trace-based just-in-time compiler LuaJIT" (4.3 Optimisation),
  https://raw.githubusercontent.com/MethodicalAcceleratorDesign/MADdocs/master/luajit/luajit-doc.pdf
- IR: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_iropt.h
- LuaJIT tests, https://github.com/tarantool/luajit/tree/tarantool/test/LuaJIT-tests/opt

### Проекты для проверки эквивалентности кода для тестирования оптимизаций

- libfuzzer + solidity https://blog.soliditylang.org/2021/02/10/an-introduction-to-soliditys-fuzz-testing-approach/
- Solidity https://github.com/ethereum/solidity/tree/develop/test/formal
- https://github.com/kristerw/pysmtgcc/blob/main/smtgcc.py
- https://github.com/boogie-org/boogie
- https://github.com/p4gauntlet/gauntlet
- https://www.usenix.org/conference/osdi20/presentation/ruffy
- Alive2 для проверки оптимизаций https://web.ist.utl.pt/nuno.lopes/pubs.php?id=alive2-pldi21
- https://foss.heptapod.net/pypy/pypy/-/issues/3832
- https://github.com/MattPD/cpplinks/blob/master/compilers.correctness.md#verification
> You can use Z3 to encode the source code before and after a compiler
> optimization as a logic formula and then check whether the formulae are
> equivalent. If they are not, there is likely a semantic bug in the
> transformation pass of your compiler, meaning you have introduced a subtle
> logic mistake.
- Z3 и SQL https://cosette.cs.washington.edu/
- https://github.com/SRI-CSL/llvm2smt#what-we-do
- PyPy https://www.pypy.org/posts/2022/12/jit-bug-finding-smt-fuzzing.html
