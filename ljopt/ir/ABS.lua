local un_op = require('ljopt.ir.UnOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeABSNum = {}
ir_node.extended(impls.IRNodeABSNum, un_op.UnOpNum)

impls.IRNodeABSInt = {}
ir_node.extended(impls.IRNodeABSInt, ir_node.ir_node_base)

function impls.IRNodeABSInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local data = ('(ite (bvslt %s (_ bv0 64)) (bvneg %s) %s)'):format(
        left_op, left_op, left_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeABSI64 = {}
ir_node.extended(impls.IRNodeABSI64, un_op.UnOpI64)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.abs',
        ['i64'] = '',
        ['int'] = '',
    }
    assert(op_table[type], 'Should not be nil.')
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'ABS', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
