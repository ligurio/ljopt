local un_op = require('ljopt.ir.UnOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSWAPI64 = {}
ir_node.extended(impls.IRNodeBSWAPI64, un_op.UnOpI64)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['i64'] = 'bswap64',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BSWAP', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
