local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeMULBase = {}
ir_node.extended(IRNodeMULBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeMULNum = {}
ir_node.extended(impls.IRNodeMULNum, bin_op.BinOpNum)

impls.IRNodeMULInt = {}
ir_node.extended(impls.IRNodeMULInt, bin_op.BinOpInt)

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
        ['num'] = 'fp.mul',
        ['int'] = 'bvmul',
    }
    assert(type_table[type], 'Unsupported type for MUL operation')
    local node = impls['IRNodeMUL' .. type_table[type]]:new(
        ssa_ref, flags, type, 'MUL', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
