local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMODInt = { op_str = 'bvsrem' }
ir_node.extended(impls.IRNodeMODInt, bin_op.BinOpInt)

impls.IRNodeMODI64 = { op_str = 'bvsrem' }
ir_node.extended(impls.IRNodeMODI64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
