local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeEQBase = {}
ir_node.extended(IRNodeEQBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeEQNum = {}
ir_node.extended(impls.IRNodeEQNum, IRNodeEQBase)

function impls.IRNodeEQNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(== %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeEQInt = {}
ir_node.extended(impls.IRNodeEQInt, IRNodeEQBase)

function impls.IRNodeEQInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(== %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeEQTab = {}
ir_node.extended(impls.IRNodeEQTab, IRNodeEQBase)

function impls.IRNodeEQTab:to_smt_lib(--[[ctx]])
    -- TODO: Implement.
    return ''
end

impls.IRNodeEQFun = {}
ir_node.extended(impls.IRNodeEQFun, IRNodeEQBase)

function impls.IRNodeEQFun:to_smt_lib()
    -- TODO: Implement.
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['tab'] = 'Tab',
        ['fun'] = 'Fun',
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
    assert(type_table[type], 'Unsupported type for EQ operation ' .. type)
    return impls['IRNodeEQ' .. type_table[type]]:new(ssa_ref, flags, type, 'EQ', left_op, right_op)
end

return {
    instance = instance
}
