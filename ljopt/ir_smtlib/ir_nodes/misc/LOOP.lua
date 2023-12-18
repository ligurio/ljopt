local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

IRNodeLOOP = {}
ir_node.extended(IRNodeLOOP, ir_node.ir_node_base)

function IRNodeLOOP:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeLOOP:new(ssa_ref, flags, type, "LOOP", left_op, right_op)
end

return {
    instance = instance
}
