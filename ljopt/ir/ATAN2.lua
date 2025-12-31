local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeATAN2Num = {}
ir_node.extended(impls.IRNodeATAN2Num, bin_op.BinOpNum)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['Num'] = 'fp.atan2',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'ATAN2', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
