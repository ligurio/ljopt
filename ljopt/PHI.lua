local ir_node = require("ljopt.ir_node_base")

local IRNodePHI = {}
ir_node.extended(IRNodePHI, ir_node.ir_node_base)

function IRNodePHI:to_smt_lib()
    --TODO: Implement
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodePHI:new(ssa_ref, flags, type, "PHI", left_op, right_op)
end

return {
    instance = instance
}
