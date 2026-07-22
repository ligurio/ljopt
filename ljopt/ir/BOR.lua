local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBORI64 = { op_str = 'bvor' }
ir_node.extended(impls.IRNodeBORI64, bin_op.BinOpI64)

impls.IRNodeBORInt = { op_str = 'bvor' }
ir_node.extended(impls.IRNodeBORInt, bin_op.BinOpInt)

impls.IRNodeBORU64 = { op_str = 'bvor' }
ir_node.extended(impls.IRNodeBORU64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
