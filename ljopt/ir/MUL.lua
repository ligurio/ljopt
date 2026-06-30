local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMULNum = {
    op_str = 'fp.mul',
    const_fn = function(a, b) return a * b end
}
ir_node.extended(impls.IRNodeMULNum, bin_op.BinOpNum)

impls.IRNodeMULInt = { op_str = 'bvmul' }
ir_node.extended(impls.IRNodeMULInt, bin_op.BinOpInt)

impls.IRNodeMULU32 = { op_str = 'bvmul' }
ir_node.extended(impls.IRNodeMULU32, bin_op.BinOpU32)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
