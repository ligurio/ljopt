local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeDIVNum = {
    op_str = 'fp.div',
    const_fn = function(a, b) return a / b end
}
ir_node.extended(impls.IRNodeDIVNum, bin_op.BinOpNum)

impls.IRNodeDIVInt = { op_str = 'bvsdiv' }
ir_node.extended(impls.IRNodeDIVInt, bin_op.BinOpInt)

impls.IRNodeDIVI64 = { op_str = 'bvsdiv' }
ir_node.extended(impls.IRNodeDIVI64, bin_op.BinOpI64)

-- u64 divides unsigned. This is the one place where u64 is not
-- just i64 under a different name: `bvsdiv` on the same bit
-- pattern gives a different answer whenever an operand has its
-- top bit set.
impls.IRNodeDIVU64 = { op_str = 'bvudiv' }
ir_node.extended(impls.IRNodeDIVU64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
