local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBXORI64 = {}
ir_node.extended(impls.IRNodeBXORI64, bin_op.BinOpI64)

impls.IRNodeBXORInt = {}
ir_node.extended(impls.IRNodeBXORInt, bin_op.BinOpInt)

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['i8'] = false,
        ['u8'] = false,
        ['i16'] = false,
        ['u16'] = false,
        ['int'] = 'Int',
        ['u32'] = false,
        ['i64'] = 'I64',
        ['u64'] = false,
    }
    local op_table = {
        ['int'] = 'bvxor',
        ['i64'] = 'bvxor',
    }
    assert(type_table[type], 'Unsupported type for BXOR operation', nil)
    local node = impls['IRNodeBXOR' .. type_table[type]]:new(
        ssa_ref, flags, type, 'BXOR', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
