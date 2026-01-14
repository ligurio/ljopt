local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMULNum = { op_str = 'fp.mul' }
ir_node.extended(impls.IRNodeMULNum, bin_op.BinOpNum)

impls.IRNodeMULInt = { op_str = 'bvmul' }
ir_node.extended(impls.IRNodeMULInt, bin_op.BinOpInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
