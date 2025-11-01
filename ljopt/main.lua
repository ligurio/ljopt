local ljopt = require("ljopt")
local is_json, json = pcall(require, "json")
local jit = require("jit")
local utils = require("ljopt.utils")
local smt_context = require('ljopt.ir.smt_context')

local is_debug = os.getenv("DEBUG")

-- Documentation: https://luajit.org/running.html
local lj_unoptimized = "jit.opt.start(0, '-fold', '+cse', '+fwd', 'hotloop=1', 'hotexit=1')"
local lj_optimized = "jit.opt.start(0, '+fold', '+cse', '+fwd', 'hotloop=1', 'hotexit=1')"

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

assert(load(lj_unoptimized))()

local traces_unopt, snapshots_unopt = ljopt.ir.record(lua_code, is_debug)
print("UNOPTIMIZE ==============================================")
assert(type(traces_unopt) == "table")
assert(load(lj_optimized))()
local traces_opt, snapshots_opt = ljopt.ir.record(lua_code, is_debug)
assert(type(traces_opt) == "table")

if is_json and is_debug then
  local traces_buf = json.encode(traces)
  io.stdout:write(traces_buf .. "\n")
end

local traces_smtlib = [[
(set-option :print-success false)
(set-option :produce-models true)
]]

for tr_n, tr_ir in pairs(traces_unopt) do
  local ctx_src = smt_context.SMTContext:new('BV', 'BV')
  traces_smtlib = traces_smtlib .. ctx_src.vm_stack:init_smt("vm_" .. tr_n) .. '\n'
  local tr_smtlib_unopt, snap_unopt = ljopt.ir.translate(tr_ir, snapshots_unopt[tr_n], "unopt", tr_n, ctx_src)
  local tr_smtlib_opt, snap_opt = ljopt.ir.translate(traces_opt[tr_n], snapshots_opt[tr_n], "opt", tr_n, ctx_src)

  if not tr_smtlib_unopt or #tr_smtlib_unopt == 0 or not tr_smtlib_opt or #tr_smtlib_opt == 0 then
    local msg = ("translation of trace %d to SMT-LIB has failed\n"):format(tr_n)
    io.stderr:write(msg)
    goto continue
  end
  traces_smtlib = traces_smtlib .. tr_smtlib_unopt .. "\n"
  traces_smtlib = traces_smtlib .. tr_smtlib_opt .. "\n"

  local merged_snaps = utils.merge_tables_named(snap_unopt, snap_opt)
  traces_smtlib = traces_smtlib .. "(assert (or false\n"
  for snap_id, values in pairs(merged_snaps) do
    local value1, value2 = values.value1, values.value2
    if (value1 ~= nil) then
      local merged_snap = utils.merge_tables_named(value1, value2)
      for slot_id, snap in pairs(merged_snap) do
        local val1, val2 = snap.value1, snap.value2
        traces_smtlib = traces_smtlib .. "    (not (= " .. val1 .. " " .. val2 .. "))\n"
      end
    end
  end
  traces_smtlib = traces_smtlib .. "))\n"
  traces_smtlib = traces_smtlib .. "(check-sat)\n(get-model)\n(reset)\n" -- Check and reset current trace
  ::continue::
end
local file = io.open("tmp.smt", "w")
file:write(traces_smtlib .. "\n")
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
