local ljopt = require("ljopt")

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

-- Documentation: https://luajit.org/running.html
local lj_opt = "jit.opt.start(0, 'hotloop=1', 'hotexit=1')"

print("LuaJIT flags:", lj_opt .. "\n")

loadstring(lj_opt)
ljopt.ir.record(lua_code)
ljopt.bc.record(lua_code)
