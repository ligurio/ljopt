local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMINNum = {}
ir_node.extended(impls.IRNodeMINNum, bin_op.BinOpNum)

impls.IRNodeMINInt = {}
ir_node.extended(impls.IRNodeMINInt, bin_op.BinOpInt)

function impls.IRNodeMINInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(ite (bvsle %s %s) %s %s)',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeMINI64 = {}
ir_node.extended(impls.IRNodeMINI64, bin_op.BinOpI64)

function impls.IRNodeMINI64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format('(ite (bvsle %s %s) %s %s))',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end


local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.min',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'MIN', left_op, right_op
    )
    node.op_str = op_table[type]
    node.ignore_rounding = true
    return node
end

return {
    instance = instance
}
