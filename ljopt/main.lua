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
  io.stderr:write("LuaJIT version mismatch.\n")
  os.exit(exit_codes.critical)
end

local lua_code = arg[1]
if lua_code == nil or
   lua_code == "-" then
  lua_code = io.stdin:read("*a") -- read the complete stdin
end

-- print(lua_code)

-- Lua treats any independent chunk as the body of an anonymous function. For
-- instance, for the chunk "a = 1", loadstring returns the equivalent of
-- `function () a = 1 end`.
-- https://www.lua.org/pil/8.html

local fn, err = loadstring(lua_code)
if fn == nil then
  io.stderr:write(("cannot load Lua code: %s.\n"):format(err))
  os.exit(exit_codes.fatals)
end

local function bc_dump(f)
  -- https://luajit.org/extensions.html#string_dump
  local bc = string.dump(f)
  assert(bc, "bytecode is nil")
end

local function ir_dump(f)
  -- TODO
end

local function bc_parse(f)
  -- TODO
end

local function ir_parse(f)
  local name = "dump.txt"
  -- ljopt.ir.dump.on(name)
  -- f()
  -- ljopt.ir.dump.off()
end

-- https://luajit.org/running.html
local default_states = {
  "jit.opt.start(0, 'hotloop=1', 'hotexit=1')",
  "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
}

local states = default_states
local ir_res = {}
local bc_res = {}
for i, state in ipairs(states) do
  io.stdout:write(state .. "\n")
  -- TODO: print current LuaJIT state.
  local raw_bc = bc_dump(fn)
  bc_res[i] = bc_parse(raw_bc)
  local raw_ir = ir_dump(fn)
  ir_res[i] = ir_parse(raw_ir)
end

-- local code = [[
-- -- TNEW.
-- -- local result
-- local stored_tab = {1}
-- local slot = {}

-- jit.opt.start('hotloop=1')

-- -- TDUP.
-- for _ = 1, 3 do
--   local t = slot
--   local result = t[1]
--   slot = _ % 2 ~= 0 and stored_tab or {true}
-- end
-- ]]

-- TODO: compare results in ir_res and bc_res.
