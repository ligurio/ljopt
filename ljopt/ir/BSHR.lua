local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSHRI64 = {}
ir_node.extended(impls.IRNodeBSHRI64, bin_op.BinOpI64)

impls.IRNodeBSHRInt = {}
ir_node.extended(impls.IRNodeBSHRInt, bin_op.BinOpInt)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['i64'] = 'bvashr',
        ['int'] = 'bvashr',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BSHR', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
