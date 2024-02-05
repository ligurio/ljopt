local ir_node = require("ljopt.ir_node_base")

local IRNodeCNEWI = {}
ir_node.extended(IRNodeCNEWI, ir_node.ir_node_base)

function IRNodeCNEWI:to_smt_lib()
    --todo: implement
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeCNEWI:new(ssa_ref, flags, type, "CNEWI", left_op, right_op)
end

return {
    instance = instance
}
