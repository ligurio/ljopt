local ir_node = require("ljopt.ir_node_base")

local IRNodeABCBase = {}
ir_node.extended(IRNodeABCBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeABCInt = {}
ir_node.extended(impls.IRNodeABCInt, ir_node.ir_node_base)

function impls.IRNodeABCInt:to_smt_lib()
    --TODO: Implement
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ["int"] = "Int",
    }
    assert(type_table[type] ~= nil, "Unsupported type for ABC operation", nil)
    return impls["IRNodeABC" .. type_table[type]]:new(ssa_ref, flags, type, "ABC", left_op, right_op)
end

return {
    instance = instance
}
