local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSARI64 = {}
ir_node.extended(impls.IRNodeBSARI64, bin_op.BinOpI64)

impls.IRNodeBSARInt = {}
ir_node.extended(impls.IRNodeBSARInt, bin_op.BinOpInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['int'] = 'bvashr',
        ['i64'] = 'bvashr',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BSAR', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
