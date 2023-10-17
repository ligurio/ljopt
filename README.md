## Translate LuaJIT IR to SMT

### Usage

- Setup dependencies: `$ apt install -y luajit z3`.
- Lua code: `$C = "for i = 1, 4 do a = i + 1 end"`
- Record LJ IR output without `dce`: `luajit -O-dce -Ohotloop=1 -Ohotexit=1 -e "require('jtbl').on()" -e "$C"`
- Record LJ IR output with `dce`: `luajit -Odce -Ohotloop=1 -Ohotexit=1 -e "require('jtbl').on()" -e "$C"`
- Translate `sample_with_dce.txt` to `sample_with_dce.smt`.
- Translate `sample_wo_dce.txt` to `sample_wo_dce.smt`.
- Run Z3: `z3 sample.smt`

```
$ lj2smt sammple.lua > sample.smt
```

### Examples

```sh
luajit -O-dse -jdump=i opt-tests/dse/array.lua
luajit -Odse -jdump=i opt-tests/dse/array.lua
luajit -O-dse -jdump=i opt-tests/dse/field.lua
luajit -Odse -jdump=i opt-tests/dse/field.lua
luajit -O-fold -jdump=i opt-tests/fold/kfold.lua
luajit -Ofold -jdump=i opt-tests/fold/kfold.lua
luajit -O-fwd -jdump=i opt-tests/fwd/tnew_tdup.lua
luajit -Ofwd -jdump=i opt-tests/fwd/tnew_tdup.lua
```

### Lua API

As any module, you have to `require()` it first.

`local ljir = require('ljir')`

**`ljir.on()`**

Starts recording all JIT events and traces.

**`ljir.off()`**

Stops recording and performs any processing and cross references needed to
actually generate a report.
