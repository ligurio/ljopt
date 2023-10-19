local dump_bc = require("lj-opt.dump_bc")
local dump_ir = require("lj-opt.dump_ir")

return {
    translate_ir = dump_ir,
    translate_bc = dump_bc,
}
