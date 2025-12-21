local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeULEBase = {}
ir_node.extended(IRNodeULEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeULEInt = {}
ir_node.extended(impls.IRNodeULEInt, IRNodeULEBase)

function impls.IRNodeULEInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvsgt %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['num'] = false,
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
    assert(type_table[type], 'Unsupported type for ULE operation')
    return impls['IRNodeULE' ..
        type_table[type]]:new(ssa_ref, flags, type, 'ULE', left_op, right_op
    )
end

return {
    instance = instance
}
