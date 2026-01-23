local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMAXNum = { op_str = 'fp.max', ignore_rounding = true }
ir_node.extended(impls.IRNodeMAXNum, bin_op.BinOpNum)

impls.IRNodeMAXInt = {}
ir_node.extended(impls.IRNodeMAXInt, bin_op.BinOpInt)

function impls.IRNodeMAXInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, self:get_type())
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, self:get_type())
    local data = string.format('(ite (bvsge %s %s) %s %s)',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeMAXI64 = {}
ir_node.extended(impls.IRNodeMAXI64, bin_op.BinOpI64)

function impls.IRNodeMAXI64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_i64_op(self:get_left_op(), ctx, self:get_type())
    local right_op = ir_node.retrieve_i64_op(self:get_right_op(), ctx, self:get_type())
    local data = string.format('(ite (bvsge %s %s) %s %s))',
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
