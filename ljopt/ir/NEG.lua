local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeNEGBase = {}
ir_node.extended(IRNodeNEGBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeNEGInt = {}
ir_node.extended(impls.IRNodeNEGInt, IRNodeNEGBase)

function impls.IRNodeNEGInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local data = string.format('(- %s)', left_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeNEGNum = {}
ir_node.extended(impls.IRNodeNEGNum, IRNodeNEGBase)

function impls.IRNodeNEGNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local data = string.format('(fp.neg %s)', left_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

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
    assert(type_table[type], 'Unsupported type for NEG operation')
    return impls['IRNodeNEG' ..
        type_table[type]]:new(ssa_ref, flags, type, 'NEG', left_op, right_op
    )
end

return {
    instance = instance
}
