local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeADDBase = {}
ir_node.extended(IRNodeADDBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeADDNum = {}
ir_node.extended(impls.IRNodeADDNum, IRNodeADDBase)

function impls.IRNodeADDNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(fp.add roundNearestTiesToEven %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeADDInt = {}
ir_node.extended(impls.IRNodeADDInt, IRNodeADDBase)

function impls.IRNodeADDInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvadd %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
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
    assert(type_table[type], 'Unsupported type for ADD operation')
    return impls['IRNodeADD' .. type_table[type]]:new(ssa_ref, flags, type, 'ADD', left_op, right_op)
end

return {
    instance = instance
}
