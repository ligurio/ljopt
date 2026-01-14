local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeSUBNum = { op_str = 'fp.sub' }
ir_node.extended(impls.IRNodeSUBNum, bin_op.BinOpNum)
impls.IRNodeSUBInt = { op_str = 'bvsub' }
ir_node.extended(impls.IRNodeSUBInt, bin_op.BinOpInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
