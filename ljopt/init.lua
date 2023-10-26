local dump_bc = require("ljopt.dump_bc")
local dump_ir = require("ljopt.dump_ir")

local parse_bc = require("ljopt.parse_bc")
local parse_ir = require("ljopt.parse_ir")

return {
    translate_ir = dump_ir,
    translate_bc = dump_bc,

   _VERSION = "0.0.1"
}
