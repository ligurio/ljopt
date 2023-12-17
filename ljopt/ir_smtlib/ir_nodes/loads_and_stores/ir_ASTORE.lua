local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

IRNodeASTORE = {}
ir_node.extended(IRNodeASTORE, ir_node.ir_node_base)

function IRNodeASTORE:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeASTORE:new(ssa_ref, flags, type, "ASTORE", left_op, right_op)
end

return {
    instance = instance
}
