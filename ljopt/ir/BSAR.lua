local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSARI64 = { op_str = 'bvashr' }
ir_node.extended(impls.IRNodeBSARI64, bin_op.BinOpShiftI64)

impls.IRNodeBSARInt = { op_str = 'bvashr' }
ir_node.extended(impls.IRNodeBSARInt, bin_op.BinOpShiftInt)

impls.IRNodeBSARU64 = { op_str = 'bvashr' }
ir_node.extended(impls.IRNodeBSARU64, bin_op.BinOpShiftI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
