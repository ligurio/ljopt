local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeSUBOVNum = {}
ir_node.extended(impls.IRNodeSUBOVNum, bin_op.BinOpNum)
impls.IRNodeSUBOVInt = {}
ir_node.extended(impls.IRNodeSUBOVInt, bin_op.BinOpInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.sub',
        ['int'] = 'bvsub',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'SUBOV', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
