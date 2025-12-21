local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeULENum = {}
ir_node.extended(impls.IRNodeULENum, bin_op.BinOpGuardNum)
impls.IRNodeULEInt = {}
ir_node.extended(impls.IRNodeULEInt, bin_op.BinOpGuardInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.leq',
        ['int'] = 'bvule',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'ULE', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
