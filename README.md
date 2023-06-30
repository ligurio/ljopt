## LuaJIT IR to SMT

### Usage

- Setup package dependencies: `$ apt install -y luajit z3`
- Create a `sample.lua`: `echo "for i in ipairs({1, 2, 3, 4, 5}) do print(i) end" > sample.lua`
- Translate `sample.lua` to `sample.z3`: `luajit -lloom -e 'loom.on()' > sample.z3`
- Run Z3: `z3 sample.z3`

### Examples

```sh
LUA_PATH='src/?.lua;test/tarantool-tests/?.lua;;' ./src/luajit -O-dse -jdump=i test/LuaJIT-tests/opt/dse/array.lua
LUA_PATH='src/?.lua;test/tarantool-tests/?.lua;;' ./src/luajit -Odse -jdump=i test/LuaJIT-tests/opt/dse/field.lua
LUA_PATH='src/?.lua;test/tarantool-tests/?.lua;;' ./src/luajit -O-fold -jdump=i test/LuaJIT-tests/opt/fold/kfold.lua
LUA_PATH='src/?.lua;test/tarantool-tests/?.lua;;' ./src/luajit -Ofold -jdump=i test/LuaJIT-tests/opt/fold/kfold.lua
LUA_PATH='src/?.lua;test/tarantool-tests/?.lua;;' ./src/luajit -O-fwd -jdump=i test/LuaJIT-tests/opt/fwd/tnew_tdup.lua
LUA_PATH='src/?.lua;test/tarantool-tests/?.lua;;' ./src/luajit -Ofwd -jdump=i test/LuaJIT-tests/opt/fwd/tnew_tdup.lua
```

### As a command line argument

Just put it in a `jit/` directory within `package.path` or `$LUA_PATH`,
typically `'/usr/local/share/luajit-2.1..../jit/'`; but it also works in
`'/usr/local/share/lua/5.1/jit/'` or even `'./jit/'`.  Then it can be used as
an argument to LuaJIT in the form:

**`-jloom[=<out>]`**

`<out>` is an output file name (default `io.stdout`).

### Lua API

If you want to report traces on just part of your code, it's better to use it
explicitly.

As any module, you have to `require()` it first.

`local loom = require('jit.loom')`

**`loom.start(out)`**

Implements the `-jloom[=out]` option. The `out` parameter is either a writeable
open file, defaults to `io.stdout`.  When the Lua VM is terminated normally,
`loom.off()` is called with the reporting function created by the given
template.

**`loom.on()`**

Starts recording all JIT events and traces.

**`loom.off()`**

Stops recording and performs any processing and cross references needed to
actually generate a report.

```lua
traces, funcs = loom.off()
report = loom.off([f [, ...]])
```

Called without any arguments, returns two Lua tables, one with the processed
trace information and a second one with all the functions involved in those
traces execution.

The second form is equivalent to:

```lua
do
    local traces, funcs = loom.off()
    report = f(traces, funcs, ...)
end
```

That is, both return values (the `traces` and `funcs` arrays) are passed to the
given function `f`, together with any extra argument, and returns any return
value(s) of `f`.

**`loom.annotated(funcs, traces)`**

Returns an annotated listing of the source code of the given `funcs` and
`traces` arrays.
