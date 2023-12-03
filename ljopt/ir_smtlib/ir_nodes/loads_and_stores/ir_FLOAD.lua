local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_FLOAD = {}
ir_node.extended(ir_node_FLOAD, ir_node.ir_node_base)

function ir_node_FLOAD:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    return ir_node_FLOAD:new(ssa_ref, flags, type, "FLOAD", left_op, right_op)
end

return {
    instance = instance
}
