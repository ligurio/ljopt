local un_op = require('ljopt.ir.UnOp')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeNEGBase = {}
ir_node.extended(IRNodeNEGBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeNEGInt = {}
ir_node.extended(impls.IRNodeNEGInt, un_op.UnOpInt)

impls.IRNodeNEGNum = {}
ir_node.extended(impls.IRNodeNEGNum, un_op.UnOpNum)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.neg',
        ['int'] = 'bvneg',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'NEG', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
