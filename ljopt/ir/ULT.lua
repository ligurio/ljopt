local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeULTNum = { op_str = 'fp.lt' }
ir_node.extended(impls.IRNodeULTNum, bin_op.BinOpGuardInt)
impls.IRNodeULTInt = { op_str = 'bvslt' }
ir_node.extended(impls.IRNodeULTInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
