local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeNEInt = {}
ir_node.extended(impls.IRNodeNEInt, bin_op.BinOpGuardInt)
impls.IRNodeNENum = {}
ir_node.extended(impls.IRNodeNENum, bin_op.BinOpGuardNum)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'distinct',
        ['int'] = 'distinct',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'NE', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
