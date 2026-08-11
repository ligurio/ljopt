local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeADDOVInt = {
    op_str = 'bvadd',
    const_fn = function(a, b) return a + b end,
}
ir_node.extended(impls.IRNodeADDOVInt, bin_op.BinOpOvInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
