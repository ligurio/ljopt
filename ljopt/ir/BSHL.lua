local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSHLI64 = { op_str = 'bvshl' }
ir_node.extended(impls.IRNodeBSHLI64, bin_op.BinOpI64)

impls.IRNodeBSHLInt = { op_str = 'bvshl' }
ir_node.extended(impls.IRNodeBSHLInt, bin_op.BinOpShiftInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
