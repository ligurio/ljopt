## Translate LuaJIT BC and IR to SMT-LIB

is an implementation of translation validation for LuaJIT.

### Usage

- Setup dependencies: `apt install -y luajit z3`.
- Translate:
  - `LUA_PATH='./ljopt/init.lua;./ljopt/?.lua;;' ljopt "for i = 1, 4 do a = i + 1 end" > sample.smt2`.
  - `cat trash/opt-tests/fwd/tnew_tdup.lua | LUA_PATH='./ljopt/init.lua;./ljopt/?.lua;;' ./bin/ljopt > sample.smt2`
- Validate with Z3: `z3 -smt2 sample.smt2`.

### License

The MIT License, see LICENSE.
