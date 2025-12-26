local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeBANDBase = {}
ir_node.extended(IRNodeBANDBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeBANDI64 = {}
ir_node.extended(impls.IRNodeBANDI64, IRNodeBANDBase)

function impls.IRNodeBANDI64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format('(ext_rotate_left %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['i8'] = false,
        ['u8'] = false,
        ['i16'] = false,
        ['u16'] = false,
        ['int'] = false,
        ['u32'] = false,
        ['i64'] = 'I64',
        ['u64'] = false,
    }
    assert(type_table[type], 'Unsupported type for BROL operation')
    return impls['IRNodeBAND' ..
        type_table[type]]:new(ssa_ref, flags, type, 'BROL', left_op, right_op
    )
end

return {
    instance = instance
}
