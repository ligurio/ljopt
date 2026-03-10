local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeADDNum = {
    op_str = 'fp.add',
    const_fn = function(a, b) return a + b end
}
ir_node.extended(impls.IRNodeADDNum, bin_op.BinOpNum)

impls.IRNodeADDInt = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDInt, bin_op.BinOpInt)

impls.IRNodeADDI64 = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDI64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
