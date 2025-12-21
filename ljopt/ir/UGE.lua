local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeUGENum = {}
ir_node.extended(impls.IRNodeUGENum, bin_op.BinOpGuardNum)
impls.IRNodeUGEInt = {}
ir_node.extended(impls.IRNodeUGEInt, bin_op.BinOpGuardInt)

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['num'] = "Num",
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
    assert(type_table[type], 'Unsupported type for UGE operation', nil)
    local op_table = {
        ['num'] = 'fp.gt',
        ['int'] = 'bvsge',
    }
    local node = impls['IRNodeUGE' .. type_table[type]]:new(
        ssa_ref, flags, type, 'UGE', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
