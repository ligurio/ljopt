local ir_node = require("ljopt.ir_node_base")

local IRNodeNEWREF = {}
ir_node.extended(IRNodeNEWREF, ir_node.ir_node_base)

function IRNodeNEWREF:to_smt_lib()
    --TODO: Implement
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeNEWREF:new(ssa_ref, flags, type, "NEWREF", left_op, right_op)
end

return {
    instance = instance
}
