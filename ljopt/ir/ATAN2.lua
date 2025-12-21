local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeATAN2Num = {}
ir_node.extended(impls.IRNodeATAN2Num, bin_op.BinOpNum)

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['num'] = 'Num',
        ['i8'] = false,
        ['u8'] = false,
        ['i16'] = false,
        ['u16'] = false,
        ['int'] = false,
        ['u32'] = false,
        ['i64'] = false,
        ['u64'] = false,
        ['sfp'] = false,
    }
    local op_table = {
        ['num'] = 'fp.atan2',
    }
    assert(type_table[type], 'Unsupported type for ATAN2 operation', nil)
    local node = impls['IRNodeATAN2' .. type_table[type]]:new(
        ssa_ref, flags, type, 'ATAN2', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
