local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSARI64 = {}
ir_node.extended(impls.IRNodeBSARI64, bin_op.BinOpI64)

impls.IRNodeBSARInt = {}
ir_node.extended(impls.IRNodeBSARInt, bin_op.BinOpInt)

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
        ['int'] = 'bvashr',
        ['i64'] = 'bvashr',
    }
    assert(type_table[type], 'Unsupported type for BSAR operation', nil)
    local node = impls['IRNodeBSAR' .. type_table[type]]:new(
        ssa_ref, flags, type, 'BSAR', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
