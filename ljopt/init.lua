local dump_ir = require("ljopt.ir_dump")
local dump_bc = require("ljopt.bc_dump")
local smtlib_bc = require("ljopt.bc_smtlib")
local smtlib_ir = require("ljopt.ir_smtlib.ir_smtlib")
local jit = require("jit")

if (not jit or jit.version_num ~= 20100) then
    error("Unsupported LuaJIT library version")
end

local VERSION = "0.0.1"

return {
    ir = {
	    record = dump_ir.record,
	    translate = smtlib_ir.translate,
    },
    bc = {
	    record = dump_bc.record,
	    translate = smtlib_bc.translate,
    },

    VERSION = VERSION,
}
