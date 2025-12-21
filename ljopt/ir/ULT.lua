local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeULTNum = {}
ir_node.extended(impls.IRNodeULTNum, bin_op.BinOpGuardInt)
impls.IRNodeULTInt = {}
ir_node.extended(impls.IRNodeULTInt, bin_op.BinOpGuardInt)

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['num'] = 'Num',
        ['i8'] = false,
        ['u8'] = false,
        ['i16'] = false,
        ['u16'] = false,
        ['int'] = 'Int',
        ['u32'] = false,
        ['i64'] = false,
        ['u64'] = false,
        ['sfp'] = false,
    }
    assert(type_table[type], 'Unsupported type for ULT operation', nil)
    local op_table = {
        ['num'] = 'fp.lt',
        ['int'] = 'bvslt',
    }
    local node = impls['IRNodeULT' .. type_table[type]]:new(
        ssa_ref, flags, type, 'ULT', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
