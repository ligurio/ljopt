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
        ['i8'] = false,  -- TODO: Support.
        ['u8'] = false,  -- TODO: Support.
        ['i16'] = false, -- TODO: Support.
        ['u16'] = false, -- TODO: Support.
        ['int'] = false, -- TODO: Support.
        ['u32'] = false, -- TODO: Support.
        ['i64'] = false, -- TODO: Support.
        ['u64'] = false, -- TODO: Support.
        ['sfp'] = false  -- TODO: Support.
    }
    assert(type_table[type], 'Unsupported type for MUL operation', nil)
    return impls['IRNodeMUL' .. type_table[type]]:new(ssa_ref, flags, type, 'MUL', left_op, right_op)
end

return {
    instance = instance
}
