local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')

local IRNodeADDOVBase = {}
ir_node.extended(IRNodeADDOVBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeADDOVInt = {}
ir_node.extended(impls.IRNodeADDOVInt, IRNodeADDOVBase)

function impls.IRNodeADDOVInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvadd %s %s)', left_op, right_op)
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, arith_utils.i32_overflow_check(data)),
        ctx.op_stack:store(ssa_ref, self:get_type(), data)
    )
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
    assert(type_table[type], 'Unsupported type for ADDOV operation')
    return impls['IRNodeADDOV' ..
        type_table[type]]:new(ssa_ref, flags, type, 'ADDOV', left_op, right_op
    )
end

return {
    instance = instance
}
