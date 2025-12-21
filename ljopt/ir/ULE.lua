local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeULENum = { op_str = 'fp.leq' }
ir_node.extended(impls.IRNodeULENum, bin_op.BinOpGuardNum)
impls.IRNodeULEInt = { op_str = 'bvule' }
ir_node.extended(impls.IRNodeULEInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
