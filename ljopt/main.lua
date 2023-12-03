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
if lua_code == "-" then
  lua_code = io.stdin:read("*a") -- read the complete stdin
end

if not lua_code or
   #lua_code == 0 then
  io.stderr:write("Lua chunk is empty.\n")
  os.exit(exit_codes.critical)
end

io.stdout:write(("Lua code: %s\n"):format(lua_code))
io.stdout:write("LuaJIT flags: ", lj_opt .. "\n")

loadstring(lj_opt)

local traces = ljopt.ir.record(lua_code)
assert(type(traces) == "table")

local traces_smtlib = ""
for tr_n, tr_ir in pairs(traces) do
  local tr_smtlib = ljopt.ir.translate(tr_ir)
  if not tr_smtlib or #tr_smtlib == 0 then
    local msg = ("translation of trace %d to SMT-LIB has failed\n"):format(tr_n)
    io.stderr:write(msg)
  else
    traces_smtlib = traces_smtlib .. tr_smtlib
  end
end
io.stdout:write(traces_smtlib .. "\n")

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
