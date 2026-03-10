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

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
