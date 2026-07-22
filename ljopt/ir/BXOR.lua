local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBXORI64 = { op_str = 'bvxor' }
ir_node.extended(impls.IRNodeBXORI64, bin_op.BinOpI64)

impls.IRNodeBXORInt = { op_str = 'bvxor' }
ir_node.extended(impls.IRNodeBXORInt, bin_op.BinOpInt)

impls.IRNodeBXORU64 = { op_str = 'bvxor' }
ir_node.extended(impls.IRNodeBXORU64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
