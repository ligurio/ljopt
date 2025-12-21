local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeNOP = {}
ir_node.extended(IRNodeNOP, ir_node.ir_node_base)

function IRNodeNOP:to_smt_lib()
    return ''
end

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    return IRNodeNOP:new(ssa_ref, flags, type, 'NOP', left_op, right_op)
end

return {
    instance = instance
}
