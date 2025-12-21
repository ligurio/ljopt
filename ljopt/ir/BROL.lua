local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBROLI64 = {}
ir_node.extended(impls.IRNodeBROLI64, bin_op.BinOpI64)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['i64'] = 'ext_rotate_left',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BROL', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
