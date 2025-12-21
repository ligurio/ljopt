local ir_node = require('ljopt.ir.ir_node_base')
local bin_op = require('ljopt.ir.BinOp')

local impls = {}

impls.IRNodeGENum = {}
ir_node.extended(impls.IRNodeGENum, bin_op.BinOpGuardNum)
impls.IRNodeGEInt = {}
ir_node.extended(impls.IRNodeGEInt, bin_op.BinOpGuardInt)

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
        ['num'] = 'fp.geq',
        ['int'] = 'bvsge',
    }
    assert(type_table[type], 'Unsupported type for GE operation', nil)
    local node = impls['IRNodeGE' .. type_table[type]]:new(
        ssa_ref, flags, type, 'GE', left_op, right_op)
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
