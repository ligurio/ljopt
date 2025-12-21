local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBORI64 = {}
ir_node.extended(impls.IRNodeBORI64, bin_op.BinOpI64)

impls.IRNodeBORInt = {}
ir_node.extended(impls.IRNodeBORInt, bin_op.BinOpInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['i64'] = 'bvor',
    }
    assert(op_table[type], 'Should not be nil.')
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BROL', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
