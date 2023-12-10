local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_MUL_base = {}
extended(ir_node_MUL_base, ir_node.ir_node_base)

local impls = {}

impls.ir_node_MUL_num = {}
extended(impls.ir_node_MUL_num, ir_node_MUL_base)

function impls.ir_node_MUL_num:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format("(fp.mul roundNearestTiesToEven %s %s)", left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.ir_node_MUL_int = {}
extended(impls.ir_node_MUL_int, ir_node_MUL_base)

function impls.ir_node_MUL_int:to_smt_lib()
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
        "int", -- TODO: Support.
        "u32", -- TODO: Support.
        "i64", -- TODO: Support.
        "u64", -- TODO: Support.
        "sfp"  -- TODO: Support.
    }
    assert(type_table[type] ~= nil, "Unsupported type for MUL operation", nil)
    return impls["ir_node_MUL_" .. type]:new(ssa_ref, flags, type, "MUL", left_op, right_op)
end

return {
    instance = instance
}
