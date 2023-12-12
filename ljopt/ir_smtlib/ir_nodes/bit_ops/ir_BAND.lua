local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_BAND_base = {}
extended(ir_node_BAND_base, ir_node.ir_node_base)

local impls = {}

impls.ir_node_BAND_int = {}
extended(impls.ir_node_BAND_int, ir_node_BAND_base)

function impls.ir_node_BAND_int:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format("(bvand %s %s)", left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.ir_node_BAND_i64 = {}
extended(impls.ir_node_BAND_i64, ir_node_BAND_base)

function impls.ir_node_BAND_i64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format("(bvand %s %s)", left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        "i8",  -- TODO: Support.
        "u8",  -- TODO: Support.
        "i16", -- TODO: Support.
        "u16", -- TODO: Support.
        ["int"] = {},
        "u32", -- TODO: Support.
        ["i64"] = {},
        "u64", -- TODO: Support.
    }
    assert(type_table[type] ~= nil, "Unsupported type for BAND operation", nil)
    return impls["ir_node_BAND_" .. type]:new(ssa_ref, flags, type, "BAND", left_op, right_op)
end

return {
    instance = instance
}

