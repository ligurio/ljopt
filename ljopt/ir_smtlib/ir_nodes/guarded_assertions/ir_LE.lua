local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_LE_base = {}
extended(ir_node_LE_base, ir_node.ir_node_base)

local impls = {}

impls.ir_node_LE_int = {}
extended(impls.ir_node_LE_int, ir_node_LE_base)

function impls.ir_node_LE_int:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format("(bvsgt %s %s)", left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        "num", -- TODO: Support.
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
    assert(type_table[type] ~= nil, "Unsupported type for LE operation", nil)
    return impls["ir_node_LE_" .. type]:new(ssa_ref, flags, type, "LE", left_op, right_op)
end

return {
    instance = instance
}
