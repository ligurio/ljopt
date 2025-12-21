local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBROLI64 = {}
ir_node.extended(impls.IRNodeBROLI64, bin_op.BinOpI64)

impls.IRNodeBROLInt = {}
ir_node.extended(impls.IRNodeBROLInt, bin_op.BinOpInt)

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
        ['i64'] = 'bvor',
    }
    assert(type_table[type], 'Unsupported type for BROL operation', nil)
    local node = impls['IRNodeBROL' .. type_table[type]]:new(
        ssa_ref, flags, type, 'BROL', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
