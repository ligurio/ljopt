local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeMULBase = {}
ir_node.extended(IRNodeMULBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeMULNum = {}
ir_node.extended(impls.IRNodeMULNum, IRNodeMULBase)

function impls.IRNodeMULNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(fp.mul roundNearestTiesToEven %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeMULInt = {}
ir_node.extended(impls.IRNodeMULInt, IRNodeMULBase)

function impls.IRNodeMULInt:to_smt_lib()
    -- TODO: Implement.
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['num'] = 'Num',
        ['i8'] = false,
        ['u8'] = false,
        ['i16'] = false,
        ['u16'] = false,
        ['int'] = false,
        ['u32'] = false,
        ['i64'] = false,
        ['u64'] = false,
        ['sfp'] = false,
    }
    assert(type_table[type], 'Unsupported type for MUL operation')
    return impls['IRNodeMUL' .. type_table[type]]:new(ssa_ref, flags, type, 'MUL', left_op, right_op)
end

return {
    instance = instance
}
