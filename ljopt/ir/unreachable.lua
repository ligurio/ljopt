-- Opcodes that cannot reach the translator as this tool is built
-- and run. Registering them with an assert rather than leaving
-- them unimplemented is the difference between finding out the
-- assumption broke and quietly verifying less than it looks.
--
-- Only for opcodes ruled out by construction. An opcode that is
-- merely unmodelled belongs in the NYI path, which degrades.
local ir_node = require('ljopt.ir.ir_node_base')

local reasons = {
    PVAL = 'side traces are disabled in ir_dump_utils, and PVAL ' ..
        'forwards a parent trace value, so no trace here has one',
    HIOP = 'it carries the high word of a split 64-bit operation, ' ..
        'which only 32-bit and soft-float builds emit',
}

local IRNodeUnreachable = {}
ir_node.extended(IRNodeUnreachable, ir_node.ir_node_base)

function IRNodeUnreachable:to_smt_lib(_ctx)
    local opcode = self:get_opcode()
    assert(false, ('%s reached the translator, but %s'):format(
        opcode, reasons[opcode] or 'it was believed unreachable'
    ))
end

local function instance(_node_str)
    return IRNodeUnreachable
end

return {
    instance = instance
}
