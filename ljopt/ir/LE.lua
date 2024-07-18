local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeLEBase = {}
ir_node.extended(IRNodeLEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeLEInt = {}
ir_node.extended(impls.IRNodeLEInt, IRNodeLEBase)

function impls.IRNodeLEInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvsgt %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeLENum = {}
ir_node.extended(impls.IRNodeLENum, IRNodeLEBase)

function impls.IRNodeLENum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(<= %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['num'] = 'Num',
        ['i8'] = false,  -- TODO: Support.
        ['u8'] = false,  -- TODO: Support.
        ['i16'] = false, -- TODO: Support.
        ['u16'] = false, -- TODO: Support.
        ['int'] = 'Int',
        ['u32'] = false, -- TODO: Support.
        ['i64'] = false, -- TODO: Support.
        ['u64'] = false, -- TODO: Support.
        ['sfp'] = false  -- TODO: Support.
    }
    assert(type_table[type], 'Unsupported type for LE operation', nil)
    return impls['IRNodeLE' .. type_table[type]]:new(ssa_ref, flags, type, 'LE', left_op, right_op)
end

return {
    instance = instance
}
