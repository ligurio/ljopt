local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

IRNodeNEBase = {}
extended(IRNodeNEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeNEInt = {}
extended(impls.IRNodeNEInt, IRNodeNEBase)

function impls.IRNodeNEInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format("(distinct %s %s)", left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeNENum = {}
extended(impls.IRNodeNENum, IRNodeNEBase)

function impls.IRNodeNENum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format("(distinct %s %s)", left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ["num"] = "Num",
        "i8",  -- TODO: Support.
        "u8",  -- TODO: Support.
        "i16", -- TODO: Support.
        "u16", -- TODO: Support.
        ["int"] = "Int",
        "u32", -- TODO: Support.
        "i64", -- TODO: Support.
        "u64", -- TODO: Support.
        "sfp"  -- TODO: Support.
    }
    assert(type_table[type] ~= nil, "Unsupported type for NE operation", nil)
    return impls["IRNodeNE" .. type_table[type]]:new(ssa_ref, flags, type, "NE", left_op, right_op)
end

return {
    instance = instance
}

