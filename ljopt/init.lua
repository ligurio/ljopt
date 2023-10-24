local dump_bc = require("ljopt.dump_bc")
local dump_ir = require("ljopt.dump_ir")

return {
    translate_ir = dump_ir,
    translate_bc = dump_bc,
}
