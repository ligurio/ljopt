local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeFPMATHNum = {}
ir_node.extended(impls.IRNodeFPMATHNum, bin_op.BinOpNum)
impls.IRNodeFPMATHInt = {}
ir_node.extended(impls.IRNodeFPMATHInt, bin_op.BinOpInt)

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
        ['num'] = 'fp.sub',
        ['int'] = 'bvsub',
    }
    assert(type_table[type], 'Unsupported type for FPMATH operation', nil)
    local node = impls['IRNodeFPMATH' .. type_table[type]]:new(
        ssa_ref, flags, type, 'FPMATH', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
