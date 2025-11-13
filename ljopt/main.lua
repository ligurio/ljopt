local ljopt = require("ljopt")
local is_json, json = pcall(require, "json")
local jit = require("jit")
local smt_context = require('ljopt.ir.smt_context')

local is_debug = os.getenv("DEBUG")

-- Documentation: https://luajit.org/running.html
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

local lua_code = arg[1]
if lua_code == "-" then
  lua_code = io.stdin:read("*a") -- read the complete stdin
end

if not lua_code or
   #lua_code == 0 then
  io.stderr:write("Lua chunk is empty.\n")
  os.exit(exit_codes.critical)
end

if is_debug then
  io.stdout:write(("Lua code: %s\n"):format(lua_code))
  io.stdout:write(("LuaJIT flags: %s\n"):format(lj_opt))
end

local result = ljopt.ir.generate_smt_formula(lua_code, is_debug, true)
local file = io.open("tmp.smt", "w")
file:write(result .. "\n")
file:close()

local bc = ljopt.bc.record(lua_code) -- TODO: Wrap with pcall.
if #bc == 0 then
  io.stderr:write("no bytecode\n")
  -- os.exit(exit_codes.errors)
end

local bc_smtlib = ljopt.bc.translate(bc) -- TODO: Wrap with pcall.
if not bc_smtlib or #bc_smtlib == 0 then
  io.stderr:write("translation BC to SMT-LIB has failed\n")
  -- os.exit(exit_codes.errors)
else
  io.stdout:write("BC SMT-LIB:\n")
  io.stdout:write(bc_smtlib)
end
