local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeULENum = {}
ir_node.extended(impls.IRNodeULENum, bin_op.BinOpGuardNum)
impls.IRNodeULEInt = {}
ir_node.extended(impls.IRNodeULEInt, bin_op.BinOpGuardInt)

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
    local op_table = {
        ['num'] = 'fp.leq',
        ['int'] = 'bvule',
    }
    assert(type_table[type], 'Unsupported type for ULE operation')
    local node = impls['IRNodeULE' .. type_table[type]]:new(
        ssa_ref, flags, type, 'ULE', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
