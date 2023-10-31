## Translate LuaJIT BC and IR to SMT-LIB

is an implementation of translation validation for LuaJIT.

### Usage

- Setup dependencies: `apt install -y luajit z3`.
- Translate: `ljopt "for i = 1, 4 do a = i + 1 end" > sample.smt2`.
<!--
cat trash/opt-tests/fwd/tnew_tdup.lua | LUA_PATH='./ljopt/init.lua;./ljopt/?.lua;;' ./bin/ljopt
-->
- Validate with Z3: `z3 -smt2 sample.smt2`.

### Lua API

```lua
local ljopt = require("ljopt")`
local smt
smt = ljopt.translate_bc("for i = 1, 4 do a = a + i end")
smt = ljopt.translate_ir("for i = 1, 4 do a = a + i end")
```

### License

The MIT License, see LICENSE.
