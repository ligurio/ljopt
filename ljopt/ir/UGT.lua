local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeUGTNum = {}
ir_node.extended(impls.IRNodeUGTNum, bin_op.BinOpGuardNum)
impls.IRNodeUGTInt = {}
ir_node.extended(impls.IRNodeUGTInt, bin_op.BinOpGuardInt)

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
    assert(type_table[type], 'Unsupported type for UGT operation', nil)
    local op_table = {
        ['num'] = 'fp.gt',
        ['int'] = 'bvsgt',
    }
    local node = impls['IRNodeUGT' .. type_table[type]]:new(
        ssa_ref, flags, type, 'UGT', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
