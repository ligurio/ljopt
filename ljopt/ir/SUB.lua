local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeSUBBase = {}
ir_node.extended(IRNodeSUBBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeSUBNum = {}
ir_node.extended(impls.IRNodeSUBNum, IRNodeSUBBase)

function impls.IRNodeSUBNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(fp.sub roundNearestTiesToEven %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeSUBInt = {}
ir_node.extended(impls.IRNodeSUBInt, IRNodeSUBBase)

function impls.IRNodeSUBInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvsub %s %s)', left_op, right_op)
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
    assert(type_table[type], 'Unsupported type for SUB operation')
    return impls['IRNodeSUB' .. type_table[type]]:new(ssa_ref, flags, type, 'SUB', left_op, right_op)
end

return {
    instance = instance
}
