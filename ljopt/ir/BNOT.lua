local un_op = require('ljopt.ir.UnOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBNOTInt = {}
ir_node.extended(impls.IRNodeBNOTInt, un_op.UnOpInt)

impls.IRNodeBNOTI64 = {}
ir_node.extended(impls.IRNodeBNOTI64, un_op.UnOpI64)

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
        ['int'] = 'bvnot',
        ['i64'] = 'bvnot',
    }
    assert(type_table[type], 'Unsupported type for BNOT operation', nil)
    local node = impls['IRNodeBNOT' .. type_table[type]]:new(
        ssa_ref, flags, type, 'BNOT', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
