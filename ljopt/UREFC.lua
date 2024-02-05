local ir_node = require("ljopt.ir_node_base")

local IRNodeUREFC = {}
ir_node.extended(IRNodeUREFC, ir_node.ir_node_base)

function IRNodeUREFC:to_smt_lib()
    --todo: implement
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeUREFC:new(ssa_ref, flags, type, "UREFC", left_op, right_op)
end

return {
    instance = instance
}

