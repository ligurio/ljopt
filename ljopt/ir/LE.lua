local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeLEBase = {}
ir_node.extended(IRNodeLEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeLEInt = {}
ir_node.extended(impls.IRNodeLEInt, bin_op.BinOpGuardInt)

impls.IRNodeLENum = {}
ir_node.extended(impls.IRNodeLENum, bin_op.BinOpGuardNum)

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
        ['int'] = 'bvsle',
    }
    assert(type_table[type], 'Unsupported type for LE operation')
    local node = impls['IRNodeLE' .. type_table[type]]:new(
        ssa_ref, flags, type, 'LE', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
