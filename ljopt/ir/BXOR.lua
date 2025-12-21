local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBXORI64 = {}
ir_node.extended(impls.IRNodeBXORI64, bin_op.BinOpI64)

impls.IRNodeBXORInt = {}
ir_node.extended(impls.IRNodeBXORInt, bin_op.BinOpInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['int'] = 'bvxor',
        ['i64'] = 'bvxor',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BXOR', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
