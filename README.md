## Translate LuaJIT BC and IR to SMT

### Usage

- Setup dependencies: `$ apt install -y luajit z3`.
- Lua code: `$C = "for i = 1, 4 do a = i + 1 end"`
- Record LJ IR output with enabled `dce`: `luajit -O+dce -Ohotloop=1 -e "require('lj-opt').check()" -e "$C"`
- Record LJ IR output without `dce`: `luajit -O-dce -Ohotloop=1 -e "require('lj-opt').check()" -e "$C"`
- Translate `sample_with_dce.txt` to `sample_with_dce.smt`.
- Translate `sample_wo_dce.txt` to `sample_wo_dce.smt`.
- Run Z3: `z3 sample.smt`

```
$ lj-opt sample.lua > sample.smt
```

### Examples

```sh
diff -u <(luajit -O-dse -jdump=i opt-tests/dse/array.lua) <(luajit -Odse -jdump=i opt-tests/dse/array.lua)
diff -u <(luajit -O-dse -jdump=i opt-tests/dse/field.lua) <(luajit -Odse -jdump=i opt-tests/dse/field.lua)
diff -u <(luajit -O-fwd -jdump=i opt-tests/fwd/tnew_tdup.lua) <(luajit -Ofwd -jdump=i opt-tests/fwd/tnew_tdup.lua)
diff -u <(luajit -O-fold -jdump=i opt-tests/dse/kfold.lua) <(luajit -Ofold -jdump=i opt-tests/fold/kfold.lua)
```

### Lua API

```lua
local ljopt = require("lj-opt")`
local smt
smt = ljopt.translate_bc("for i = 1, 4 do a = a + i end")
smt = ljopt.translate_ir("for i = 1, 4 do a = a + i end")
```
