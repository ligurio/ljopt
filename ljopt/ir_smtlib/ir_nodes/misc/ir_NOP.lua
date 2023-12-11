local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_NOP = {}
ir_node.extended(ir_node_NOP, ir_node.ir_node_base)

function ir_node_NOP:to_smt_lib()
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    return ir_node_NOP:new(ssa_ref, flags, type, "NOP", left_op, right_op)
end

return {
    instance = instance
}
