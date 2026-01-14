local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBANDInt = { op_str = 'bvand' }
ir_node.extended(impls.IRNodeBANDInt, bin_op.BinOpInt)

impls.IRNodeBANDI64 = { op_str = 'bvand' }
ir_node.extended(impls.IRNodeBANDI64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
