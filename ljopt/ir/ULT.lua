local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeULTInt = { op_str = 'bvult' }
ir_node.extended(impls.IRNodeULTInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
