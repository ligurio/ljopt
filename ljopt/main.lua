local ljopt = require("ljopt")

-- TODO
-- - bisect lj opt
-- - bisect lj opt level

--tarantool> jit.version
-----
--- LuaJIT 2.1.0-beta3
--...

--tarantool> jit.status()
-----
--- true
--- SSE2
--- SSE3
--- SSE4.1
--- BMI2
--- fold
--- cse
--- dce
--- fwd
--- dse
--- narrow
--- loop
--- abc
--- sink
--- fuse
--...


local exit_codes = {
  ok = 0,
  warnings = 1,
  errors = 2,
  fatals = 3,
  critical = 4
}

if jit == nil then
  io.stderr:write("Unsupported Lua runtime.\n")
  os.exit(exit_codes.critical)
end

if jit.version_num ~= 20100 then
  io.stderr:write("Unsupported LuaJIT version.\n")
  os.exit(exit_codes.critical)
end

local lua_code = arg[1]
if lua_code == nil or
   lua_code == "-" then
  lua_code = io.stdin:read("*a") -- read the complete stdin
end

print("Lua code:", lua_code)

-- Lua treats any independent chunk as the body of an anonymous function. For
-- instance, for the chunk "a = 1", loadstring returns the equivalent of
-- `function () a = 1 end`.
-- https://www.lua.org/pil/8.html

local fn, err = loadstring(lua_code)
if fn == nil then
  io.stderr:write(("cannot load Lua code: %s.\n"):format(err))
  os.exit(exit_codes.fatals)
end

local function bc_dump(f) -- luacheck: no unused
  -- https://luajit.org/extensions.html#string_dump
  local bc = string.dump(f)
  assert(bc, "bytecode is nil")
end

local function ir_parse(f)
  ljopt.ir.dump.on()
  f()
  ljopt.ir.dump.off()
end

-- Documentation: https://luajit.org/running.html
local lj_opt = "jit.opt.start(0, 'hotloop=1', 'hotexit=1')"
print("LuaJIT flags:", lj_opt .. "\n")

loadstring(lj_opt)
assert(fn)
ir_parse(fn)
