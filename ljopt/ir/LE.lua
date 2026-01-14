local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeLEBase = {}
ir_node.extended(IRNodeLEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeLEInt = { op_str = 'bvsle' }
ir_node.extended(impls.IRNodeLEInt, bin_op.BinOpGuardInt)

impls.IRNodeLENum = { op_str = 'fp.leq' }
ir_node.extended(impls.IRNodeLENum, bin_op.BinOpGuardNum)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
