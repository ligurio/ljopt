local ljopt = require("ljopt")
local jit = require("jit")
local utils = require("ljopt.utils")

local exit_codes = {
  OK = 0,
  ERR_BAD_LUA_RUNTIME = 1,
  ERR_BAD_LUA_CHUNK = 2,
}

if jit == nil then
  utils.fatal_msg("Unsupported Lua runtime.", exit_codes.ERR_BAD_LUA_RUNTIME)
end

local lua_code = arg[1]
if lua_code == "-" then
  lua_code = io.stdin:read("*a") -- read the complete stdin
end

if not lua_code or
   #lua_code == 0 then
  utils.fatal_msg("Lua chunk is empty.", exit_codes.ERR_BAD_LUA_CHUNK)
end

local ok, res = pcall(load, lua_code)
if not ok then
  utils.fatal_msg("Syntax error in Lua chunk: " .. res,
    exit_codes.ERR_BAD_LUA_CHUNK)
end

local err
ok, err = pcall(res)
if not ok then
  utils.fatal_msg("Runtime error: " .. err, exit_codes.ERR_BAD_LUA_CHUNK)
end
-- Check for runtime errors above may trigger trace recording,
-- flush traces before proceeding.
jit.flush()

local result = ljopt.ir.translate_to_smt(lua_code, true)
io.stdout:write(result)
os.exit(exit_codes.OK)

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
