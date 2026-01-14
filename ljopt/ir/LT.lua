local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeLTNum = { op_str = 'fp.lt' }
ir_node.extended(impls.IRNodeLTNum, bin_op.BinOpGuardNum)

impls.IRNodeLTInt = { op_str = 'bvslt' }
ir_node.extended(impls.IRNodeLTInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
