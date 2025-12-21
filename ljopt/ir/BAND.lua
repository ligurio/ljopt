local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBANDInt = {}
ir_node.extended(impls.IRNodeBANDInt, bin_op.BinOpInt)

impls.IRNodeBANDI64 = {}
ir_node.extended(impls.IRNodeBANDI64, bin_op.BinOpI64)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['int'] = 'bvand',
        ['i64'] = 'bvand',
    }
    assert(op_table[type], 'Should not be nil.')
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BAND', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
