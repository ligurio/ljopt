local dump_ir = require("ljopt.ir_dump")
local dump_bc = require("ljopt.bc_dump")
local parse_bc = require("ljopt.bc_parse")
local parse_ir = require("ljopt.ir_parse")
local smtlib_bc = require("ljopt.bc_smtlib")
local smtlib_ir = require("ljopt.ir_smtlib")
local jit = require("jit")

if (not jit or jit.version_num ~= 20100) then
    error("Unsupported LuaJIT library version")
end

local VERSION = "0.0.1"

return {
    ir = {
	    dump = dump_ir,
	    parse = parse_ir.parse,
	    smtlib = smtlib_ir.translate,
    },
    bc = {
	    dump = dump_bc.dump,
	    parse = parse_bc.parse,
	    smtlib = smtlib_bc.translate,
    },

    VERSION = VERSION,
}
