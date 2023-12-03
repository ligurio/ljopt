local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_EQ_base = {}
extended(ir_node_EQ_base, ir_node.ir_node_base)

local impls = {}

impls.ir_node_EQ_num = {}
extended(impls.ir_node_EQ_num, ir_node_EQ_base)

function impls.ir_node_EQ_num:to_smt_lib()
    --TODO: Implement
    return ''
end

impls.ir_node_EQ_tab = {}
extended(impls.ir_node_EQ_tab, ir_node_EQ_base)

function impls.ir_node_EQ_tab:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ["tab"] = {},
        "num", -- TODO: Support.
        "i8",  -- TODO: Support.
        "u8",  -- TODO: Support.
        "i16", -- TODO: Support.
        "u16", -- TODO: Support.
        "int", -- TODO: Support.
        "u32", -- TODO: Support.
        "i64", -- TODO: Support.
        "u64", -- TODO: Support.
        "sfp"  -- TODO: Support.
    }
    assert(type_table[type] ~= nil, "Unsupported type for EQ operation", nil)
    return impls["ir_node_EQ_" .. type]:new(ssa_ref, flags, type, "EQ", left_op, right_op)
end

return {
    instance = instance
}
