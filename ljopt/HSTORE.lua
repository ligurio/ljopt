local ir_node = require("ljopt.ir_node_base")

local IRNodeHSTORE = {}
ir_node.extended(IRNodeHSTORE, ir_node.ir_node_base)

function IRNodeHSTORE:to_smt_lib()
    --TODO: Implement
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeHSTORE:new(ssa_ref, flags, type, "HSTORE", left_op, right_op)
end

return {
    instance = instance
}
