local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeSUBNum = {
    op_str = 'fp.sub',
    const_fn = function(a, b) return a - b end
}
ir_node.extended(impls.IRNodeSUBNum, bin_op.BinOpNum)
impls.IRNodeSUBInt = { op_str = 'bvsub' }
ir_node.extended(impls.IRNodeSUBInt, bin_op.BinOpInt)
impls.IRNodeSUBI64 = { op_str = 'bvsub' }
ir_node.extended(impls.IRNodeSUBI64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
