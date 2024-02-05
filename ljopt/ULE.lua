local ir_node = require("ljopt.ir_node_base")

local IRNodeULEBase = {}
ir_node.extended(IRNodeULEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeULEInt = {}
ir_node.extended(impls.IRNodeULEInt, IRNodeULEBase)

function impls.IRNodeULEInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format("(bvsgt %s %s)", left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        "num", -- TODO: Support.
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
    assert(type_table[type] ~= nil, "Unsupported type for ULE operation", nil)
    return impls["IRNodeULE" .. type_table[type]]:new(ssa_ref, flags, type, "ULE", left_op, right_op)
end

return {
    instance = instance
}
