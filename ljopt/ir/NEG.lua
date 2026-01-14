local un_op = require('ljopt.ir.UnOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeNEGInt = { op_str = 'bvneg' }
ir_node.extended(impls.IRNodeNEGInt, un_op.UnOpInt)

impls.IRNodeNEGNum = { op_str = 'fp.neg' }
ir_node.extended(impls.IRNodeNEGNum, un_op.UnOpNum)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
