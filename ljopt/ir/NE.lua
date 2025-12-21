local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeNEInt = {}
ir_node.extended(impls.IRNodeNEInt, bin_op.BinOpGuardInt)
impls.IRNodeNENum = {}
ir_node.extended(impls.IRNodeNENum, bin_op.BinOpGuardNum)

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
        ['num'] = 'distinct',
        ['int'] = 'distinct',
    }
    assert(type_table[type], 'Unsupported type for NE operation')
    local node = impls['IRNodeNE' .. type_table[type]]:new(
        ssa_ref, flags, type, 'NE', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
