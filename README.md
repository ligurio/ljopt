## Translate LuaJIT IR to SMT

### Usage

- Setup dependencies: `$ apt install -y luajit z3`.
- Create a `sample.lua`: `echo "for i in ipairs({1, 2, 3, 4, 5}) do print(i) end" > sample.lua`
- Record LJ IR output: `luajit -l ljir -e 'ljir.on()' > sample.txt`
- Translate `sample.txt` to `sample.smt`: `luajit -e 'ljir.on()' > sample.smt`
- Run Z3: `z3 sample.smt`

### Examples

```sh
luajit -O-dse -jdump=i test/LuaJIT-tests/opt/dse/array.lua
luajit -Odse -jdump=i test/LuaJIT-tests/opt/dse/array.lua
luajit -O-dse -jdump=i test/LuaJIT-tests/opt/dse/field.lua
luajit -Odse -jdump=i test/LuaJIT-tests/opt/dse/field.lua
luajit -O-fold -jdump=i test/LuaJIT-tests/opt/fold/kfold.lua
luajit -Ofold -jdump=i test/LuaJIT-tests/opt/fold/kfold.lua
luajit -O-fwd -jdump=i test/LuaJIT-tests/opt/fwd/tnew_tdup.lua
luajit -Ofwd -jdump=i test/LuaJIT-tests/opt/fwd/tnew_tdup.lua
```

### Lua API

As any module, you have to `require()` it first.

`local ljir = require('ljir')`

**`ljir.on()`**

Starts recording all JIT events and traces.

**`ljir.off()`**

Stops recording and performs any processing and cross references needed to
actually generate a report.
