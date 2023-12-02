local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_ABC_base = {}
extended(ir_node_ABC_base, ir_node.ir_node_base)

local impls = {}

impls.ir_node_ABC_int = {}
extended(impls.ir_node_ABC_int, ir_node.ir_node_base)

function impls.ir_node_ABC_int:to_smt_lib ()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ["int"] = {},
    }
    assert(type_table[type] ~= nil, "Unsupported type for ABC operation", nil)
    return impls["ir_node_ABC_"..type].new(ssa_ref, flags, type, "ABC", left_op, right_op)
end


return{
    instance = instance
}