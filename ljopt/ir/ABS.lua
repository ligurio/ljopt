local un_op = require('ljopt.ir.UnOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeABSNum = { op_str = 'fp.abs' }
ir_node.extended(impls.IRNodeABSNum, un_op.UnOpNum)

impls.IRNodeABSInt = {}
ir_node.extended(impls.IRNodeABSInt, ir_node.ir_node_base)

function impls.IRNodeABSInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local data = ('(ite (bvslt %s (_ bv0 64)) (bvneg %s) %s)'):format(
        left_op, left_op, left_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeABSI64 = {}
ir_node.extended(impls.IRNodeABSI64, un_op.UnOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
