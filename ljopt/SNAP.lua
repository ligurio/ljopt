local ir_node = require("ljopt.ir_node_base")

local IRNodeSNAP = {}
ir_node.extended(IRNodeSNAP, ir_node.ir_node_base)

function IRNodeSNAP:to_smt_lib()
    --TODO: Implement
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeSNAP:new(ssa_ref, flags, type, "SNAP", left_op, right_op)
end

return {
    instance = instance
}
