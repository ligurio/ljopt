local dump_bc = require("ljopt.ir.dump")
local dump_ir = require("ljopt.bc.dump")
local parse_bc = require("ljopt.bc.parse")
local parse_ir = require("ljopt.ir.parse")
local smtlib_bc = require("ljopt.bc.parse")
local smtlib_ir = require("ljopt.bc.parse")

local VERSION = "0.0.1"

return {
    ir = {
	    dump = dump_ir,
	    parse = parse_ir,
	    smtlib = smtlib_ir,
    },
    bc = {
	    dump = dump_bc,
	    parse = parse_bc,
	    smtlib = smtlib_bc,
    },

    VERSION = VERSION,
}
