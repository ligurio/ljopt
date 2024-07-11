local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeBANDBase = {}
ir_node.extended(IRNodeBANDBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeBANDInt = {}
ir_node.extended(impls.IRNodeBANDInt, IRNodeBANDBase)

function impls.IRNodeBANDInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvand %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeBANDI64 = {}
ir_node.extended(impls.IRNodeBANDI64, IRNodeBANDBase)

function impls.IRNodeBANDI64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format('(bvand %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['i8'] = false,  -- TODO: Support.
        ['u8'] = false,  -- TODO: Support.
        ['i16'] = false, -- TODO: Support.
        ['u16'] = false, -- TODO: Support.
        ['int'] = 'Int',
        ['u32'] = false, -- TODO: Support.
        ['i64'] = 'I64',
        ['u64'] = false, -- TODO: Support.
    }
    assert(type_table[type], 'Unsupported type for BAND operation', nil)
    return impls['IRNodeBAND' .. type_table[type]]:new(ssa_ref, flags, type, 'BAND', left_op, right_op)
end

return {
    instance = instance
}
