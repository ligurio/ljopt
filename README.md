## LuaJIT to SMT

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

### Optimizations

#### PUC Rio Lua

- "A no-frills introduction to Lua 5 VM instructions.",
  http://underpop.free.fr/l/lua/docs/a-no-frills-introduction-to-lua-5.1-vm-instructions.pdf
- "The Implementation of Lua 5.0", https://www.lua.org/doc/jucs05.pdf
- "Optimizing Lua VM Bytecode using Global Dataflow Analysis" (Chapter 3 Optimizing),
  https://nymphium.github.io/pdf/opeth_report.pdf

#### LuaJIT

- "Tecnical Documentation trace-based just-in-time compiler LuaJIT" (4.3 Optimisation),
  https://raw.githubusercontent.com/MethodicalAcceleratorDesign/MADdocs/master/luajit/luajit-doc.pdf
- IR: https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_iropt.h
- https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_dce.c
- https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_fold.c
- https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_loop.c
- https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_mem.c
- https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_narrow.c
- https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_sink.c
- https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_opt_split.c
- https://github.com/tarantool/luajit/tree/tarantool/test/LuaJIT-tests/opt

### Exporting BC/IR

1. `luajit -b -e "local function add(a, b) return a + b end; add(1, 2)" luac.out`
2. `luajit -jdump=bi -O+loop -Ohotloop=1 -e "local function add(a, b) return a + b end; add(1, 4) add(1, 2) add(1, 54)"`
3. `luajit -jdump=bi -O+loop -Ohotloop=1 -e "local b; for i = 1, 3 do b = 20 end"`
4. `string.dump(f [,strip])`

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

</details>

### References

- `jit.dump` source code, https://github.com/LuaJIT/LuaJIT/blob/master/src/jit/dump.lua
- "Running LuaJIT", https://luajit.org/running.html#opt_b
- `string.dump` description, https://luajit.org/extensions.html#string_dump
- "SSA-IR-2.0", http://web.archive.org/web/20220607041118/http://wiki.luajit.org/SSA-IR-2.0
- "Bytecode-2.0", https://web.archive.org/web/20220717120825/http://wiki.luajit.org/Bytecode-2.0
