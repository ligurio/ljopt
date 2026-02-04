local ir_node = require('ljopt.ir.ir_node_base')
local bin_op = require('ljopt.ir.BinOp')

local impls = {}

impls.IRNodeGTNum = { op_str = 'fp.gt' }
ir_node.extended(impls.IRNodeGTNum, bin_op.BinOpGuardNum)

impls.IRNodeGTInt = { op_str = 'bvsgt' }
ir_node.extended(impls.IRNodeGTInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
