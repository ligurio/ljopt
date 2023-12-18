local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

IRNodeAREF = {}
ir_node.extended(IRNodeAREF, ir_node.ir_node_base)

function IRNodeAREF:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeAREF:new(ssa_ref, flags, type, "AREF", left_op, right_op)
end

return {
    instance = instance
}
