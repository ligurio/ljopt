local dump_ir = require("ljopt.ir_dump")
local dump_bc = require("ljopt.bc_dump")
local smtlib_bc = require("ljopt.bc_smtlib")
local smtlib_ir = require("ljopt.ir_smtlib")
local is_jit = (tostring(getmetatable):match("builtin") ~= nil)

if (not is_jit) then
    error("requires LuaJIT")
end

local jutil = require("jit.util")
if not jutil.snappc or type(jutil.snappc) ~= "function" then
    error("requires jit.util.snappc() support in LuaJIT")
end
if not jutil.tablesize or type(jutil.tablesize) ~= "function" then
    error("requires jit.util.tablesize() support in LuaJIT")
end

local VERSION = "0.0.1"

return {
    ir = {
	    record = dump_ir.record,
	    traces_to_smt = smtlib_ir.traces_to_smt,
	    translate_to_smt = smtlib_ir.translate_to_smt,
    },
    bc = {
	    record = dump_bc.record,
	    translate = smtlib_bc.translate,
    },

    VERSION = VERSION,
}
