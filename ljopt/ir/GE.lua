local ir_node = require('ljopt.ir.ir_node_base')
local bin_op = require('ljopt.ir.BinOp')

local impls = {}

impls.IRNodeGENum = { op_str = 'fp.geq' }
ir_node.extended(impls.IRNodeGENum, bin_op.BinOpGuardNum)
impls.IRNodeGEInt = { op_str = 'bvsge' }
ir_node.extended(impls.IRNodeGEInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
