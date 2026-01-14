local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeNEInt = { op_str = 'distinct' }
ir_node.extended(impls.IRNodeNEInt, bin_op.BinOpGuardInt)
impls.IRNodeNENum = { op_str = 'distinct' }
ir_node.extended(impls.IRNodeNENum, bin_op.BinOpGuardNum)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
