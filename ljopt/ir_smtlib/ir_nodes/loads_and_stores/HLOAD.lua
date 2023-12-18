local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

IRNodeHLOAD = {}
ir_node.extended(IRNodeHLOAD, ir_node.ir_node_base)

function IRNodeHLOAD:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeHLOAD:new(ssa_ref, flags, type, "HLOAD", left_op, right_op)
end

return {
    instance = instance
}

