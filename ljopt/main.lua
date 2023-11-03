local ljopt = require("ljopt")

-- Documentation: https://luajit.org/running.html
local lj_opt = "jit.opt.start(0, 'hotloop=1', 'hotexit=1')"

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

io.stdout:write("Lua code:", lua_code)
io.stdout:write("LuaJIT flags:", lj_opt .. "\n")

loadstring(lj_opt)

local traces = ljopt.ir.record(lua_code) -- TODO: Wrap with pcall.
local n_traces = #traces
if n_traces == 0 then
  io.stderr:write("there are no traces\n")
  -- os.exit(exit_codes.errors)
end

local trace = traces[1] -- FIXME
local ir_smtlib = ljopt.ir.translate(trace) -- TODO: Wrap with pcall.
if not ir_smtlib or #ir_smtlib == 0 then
  io.stderr:write("translation IR to SMT-LIB has failed\n")
  -- os.exit(exit_codes.errors)
else
  io.stdout:write("IR SMT-LIB:\n")
  io.stdout:write(ir_smtlib)
end

local bc = ljopt.bc.record(lua_code) -- TODO: Wrap with pcall.
local ops = #bc
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
