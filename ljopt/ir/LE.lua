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
    local data = string.format('(fp.leq %s %s)', left_op, right_op)
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
    assert(type_table[type], 'Unsupported type for LE operation', nil)
    return impls['IRNodeLE' .. type_table[type]]:new(ssa_ref, flags, type, 'LE', left_op, right_op)
end

return {
    instance = instance
}
