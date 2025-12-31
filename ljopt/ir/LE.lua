local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeLEBase = {}
ir_node.extended(IRNodeLEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeLEInt = {}
ir_node.extended(impls.IRNodeLEInt, bin_op.BinOpGuardInt)

impls.IRNodeLENum = {}
ir_node.extended(impls.IRNodeLENum, bin_op.BinOpGuardNum)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['num'] = 'fp.leq',
        ['int'] = 'bvsle',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'LE', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
