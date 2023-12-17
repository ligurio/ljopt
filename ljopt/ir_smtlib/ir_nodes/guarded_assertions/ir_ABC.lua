local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

IRNodeABCBase = {}
extended(IRNodeABCBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeABCInt = {}
extended(impls.IRNodeABCInt, ir_node.ir_node_base)

function impls.IRNodeABCInt:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ["int"] = {},
    }
    assert(type_table[type] ~= nil, "Unsupported type for ABC operation", nil)
    return impls["IRNodeABC" .. type]:new(ssa_ref, flags, type, "ABC", left_op, right_op)
end

return {
    instance = instance
}
