local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeADDNum = {}
ir_node.extended(impls.IRNodeADDNum, bin_op.BinOpNum)

impls.IRNodeADDInt = {}
ir_node.extended(impls.IRNodeADDInt, bin_op.BinOpInt)

impls.IRNodeADDI64 = {}
ir_node.extended(impls.IRNodeADDI64, bin_op.BinOpI64)

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
    assert(type_table[type], 'Unsupported type for ADD operation')
    local op_table = {
        ['num'] = 'fp.add',
        ['int'] = 'bvadd',
        ['i64'] = 'bvadd',
    }
    local node = impls['IRNodeADD' .. type_table[type]]:new(
        ssa_ref, flags, type, 'ADD', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
