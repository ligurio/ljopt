local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeSUBOVInt = {
    op_str = 'bvsub',
    const_fn = function(a, b) return a - b end,
}
ir_node.extended(impls.IRNodeSUBOVInt, bin_op.BinOpOvInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
