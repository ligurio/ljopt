local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_SUB_base = {}
extended(ir_node_SUB_base, ir_node.ir_node_base)

local impls = {}

impls.ir_node_SUB_num = {}
extended(impls.ir_node_SUB_num, ir_node_SUB_base)

function impls.ir_node_SUB_num:to_smt_lib()
    --TODO: Implement
    return ''
end

impls.ir_node_SUB_int = {}
extended(impls.ir_node_SUB_int, ir_node_SUB_base)

function impls.ir_node_SUB_int:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ["num"] = {},
        "i8",  -- TODO: Support.
        "u8",  -- TODO: Support.
        "i16", -- TODO: Support.
        "u16", -- TODO: Support.
        ["int"] = {},
        "u32", -- TODO: Support.
        "i64", -- TODO: Support.
        "u64", -- TODO: Support.
        "sfp"  -- TODO: Support.
    }
    assert(type_table[type] ~= nil, "Unsupported type for SUB operation", nil)
    return impls["ir_node_SUB_" .. type]:new(ssa_ref, flags, type, "SUB", left_op, right_op)
end

return {
    instance = instance
}
