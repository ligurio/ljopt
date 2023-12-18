local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

IRNodeEQBase = {}
extended(IRNodeEQBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeEQNum = {}
extended(impls.IRNodeEQNum, IRNodeEQBase)

function impls.IRNodeEQNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format("(== %s %s)", left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeEQInt = {}
extended(impls.IRNodeEQInt, IRNodeEQBase)

function impls.IRNodeEQInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format("(== %s %s)", left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeEQTab = {}
extended(impls.IRNodeEQTab, IRNodeEQBase)

function impls.IRNodeEQTab:to_smt_lib(ctx)
    --TODO: Implement
    return ''
end

impls.IRNodeEQFun = {}
extended(impls.IRNodeEQFun, IRNodeEQBase)

function impls.IRNodeEQFun:to_smt_lib()
    --TODO: Implement
    return ''
end

function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ["tab"] = "Tab",
        ["fun"] = "Fun", -- TODO: Support.
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
    assert(type_table[type] ~= nil, "Unsupported type for EQ operation "..type, nil)
    return impls["IRNodeEQ" .. type_table[type]]:new(ssa_ref, flags, type, "EQ", left_op, right_op)
end

return {
    instance = instance
}
