local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

IRNodeHREFK = {}
ir_node.extended(IRNodeHREFK, ir_node.ir_node_base)

function IRNodeHREFK:to_smt_lib()
    --todo: implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeHREFK:new(ssa_ref, flags, type, "HREFK", left_op, right_op)
end

return {
    instance = instance
}
