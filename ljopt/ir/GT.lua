local ir_node = require('ljopt.ir.ir_node_base')
local bin_op = require('ljopt.ir.BinOp')

local impls = {}

impls.IRNodeGTNum = {}
ir_node.extended(impls.IRNodeGTNum, bin_op.BinOpGuardNum)
impls.IRNodeGTInt = {}
ir_node.extended(impls.IRNodeGTInt, bin_op.BinOpGuardInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.gt',
        ['int'] = 'bvsgt',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'GT', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
