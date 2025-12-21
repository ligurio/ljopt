local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeDIVNum = {}
ir_node.extended(impls.IRNodeDIVNum, bin_op.BinOpNum)

impls.IRNodeDIVInt = {}
ir_node.extended(impls.IRNodeDIVInt, bin_op.BinOpInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.div',
        ['int'] = 'bvsdiv',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'DIV', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
