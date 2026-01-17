local ljopt = require("ljopt")
local ljopt_config = require("ljopt.config")
local jit = require("jit")

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

if ljopt_config.is_debug() then
  io.stdout:write(("Lua code: %s\n"):format(lua_code))
end

local result = ljopt.ir.translate_to_smt(lua_code, true)
io.stdout:write(result)
os.exit(exit_codes.ok)

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
