local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeUGTNum = {}
ir_node.extended(impls.IRNodeUGTNum, bin_op.BinOpGuardNum)
impls.IRNodeUGTInt = {}
ir_node.extended(impls.IRNodeUGTInt, bin_op.BinOpGuardInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.gt',
        ['int'] = 'bvsgt',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'UGT', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
