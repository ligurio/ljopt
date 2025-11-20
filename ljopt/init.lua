local dump_ir = require("ljopt.ir_dump")
local dump_bc = require("ljopt.bc_dump")
local smtlib_bc = require("ljopt.bc_smtlib")
local smtlib_ir = require("ljopt.ir_smtlib")
local is_jit = (tostring(getmetatable):match("builtin") ~= nil)

if (not is_jit) then
    error("requires LuaJIT")
end

local VERSION = "0.0.1"

return {
    ir = {
	    record = dump_ir.record,
	    translate = smtlib_ir.translate,
	    translate_to_smt = smtlib_ir.translate_to_smt,
    },
    bc = {
	    record = dump_bc.record,
	    translate = smtlib_bc.translate,
    },

    VERSION = VERSION,
}
