local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSHLI64 = {}
ir_node.extended(impls.IRNodeBSHLI64, bin_op.BinOpI64)

impls.IRNodeBSHLInt = {}
ir_node.extended(impls.IRNodeBSHLInt, bin_op.BinOpInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['int'] = 'bvshl',
        ['i64'] = 'bvshl',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BSHL', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
