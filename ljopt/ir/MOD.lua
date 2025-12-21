local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMODNum = {}
ir_node.extended(impls.IRNodeMODNum, bin_op.BinOpNum)

impls.IRNodeMODInt = {}
ir_node.extended(impls.IRNodeMODInt, bin_op.BinOpInt)

impls.IRNodeMODI64 = {}
ir_node.extended(impls.IRNodeMODI64, bin_op.BinOpI64)

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['num'] = false,
        ['i8'] = false,
        ['u8'] = false,
        ['i16'] = false,
        ['u16'] = false,
        ['int'] = 'Int',
        ['u32'] = false,
        ['i64'] = 'I64',
        ['u64'] = false,
        ['sfp'] = false,
    }
    local op_table = {
        ['int'] = 'bvsrem',
        ['i64'] = 'bvsrem',
    }
    assert(type_table[type], 'Unsupported type for MOD operation', nil)
    local node = impls['IRNodeMOD' .. type_table[type]]:new(
        ssa_ref, flags, type, 'MOD', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
