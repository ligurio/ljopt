local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMINNum = { op_str = 'fp.min', ignore_rounding = true }
ir_node.extended(impls.IRNodeMINNum, bin_op.BinOpNum)

impls.IRNodeMINInt = {}
ir_node.extended(impls.IRNodeMINInt, bin_op.BinOpInt)

function impls.IRNodeMINInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_int_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(ite (bvsle %s %s) %s %s)',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeMINI64 = {}
ir_node.extended(impls.IRNodeMINI64, bin_op.BinOpI64)

function impls.IRNodeMINI64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_i64_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_i64_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(ite (bvsle %s %s) %s %s))',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
