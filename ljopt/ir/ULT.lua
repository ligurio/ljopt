local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeULTNum = {}
ir_node.extended(impls.IRNodeULTNum, bin_op.BinOpGuardInt)
impls.IRNodeULTInt = {}
ir_node.extended(impls.IRNodeULTInt, bin_op.BinOpGuardInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.lt',
        ['int'] = 'bvslt',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'ULT', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
