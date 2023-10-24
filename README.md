## Translate LuaJIT BC and IR to SMT-LIB

is an implementation of translation validation for LuaJIT.

### Usage

- Setup dependencies: `$ apt install -y luajit z3`.
- Lua code: `$C = "for i = 1, 4 do a = i + 1 end"`
- Record LJ IR output with enabled `dce`: `luajit -O+dce -Ohotloop=1 -e "require('ljopt').check()" -e "$C"`
- Record LJ IR output without `dce`: `luajit -O-dce -Ohotloop=1 -e "require('ljopt').check()" -e "$C"`
- Translate `sample_with_dce.txt` to `sample_with_dce.smt`.
- Translate `sample_wo_dce.txt` to `sample_wo_dce.smt`.
- Run Z3: `z3 sample.smt`

```
$ ljopt sample.lua > sample.smt
```

### Lua API

```lua
local ljopt = require("ljopt")`
local smt
smt = ljopt.translate_bc("for i = 1, 4 do a = a + i end")
smt = ljopt.translate_ir("for i = 1, 4 do a = a + i end")
```

### License

The MIT License, see LICENSE.
