local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeUGENum = { op_str = 'fp.gt' }
ir_node.extended(impls.IRNodeUGENum, bin_op.BinOpGuardNum)
impls.IRNodeUGEInt = { op_str = 'bvsge' }
ir_node.extended(impls.IRNodeUGEInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
