local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

-- BSHR is the *logical* shift right (bit.rshift): zero bits
-- shift in. On a 64-bit sign-extended int cell an arithmetic
-- shift would replicate the sign, so the 32-bit result must be
-- produced from the low 32 bits and re-sign-extended afterwards.
impls.IRNodeBSHRInt = {}
ir_node.extended(impls.IRNodeBSHRInt, ir_node.ir_node_base)

function impls.IRNodeBSHRInt:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, type)
    local data = ('((_ sign_extend 32) (bvlshr ((_ extract 31 0) %s) ' ..
        '((_ extract 31 0) %s)))'):format(left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), type, data)
end

-- 64-bit logical shift right on the raw bit pattern.
impls.IRNodeBSHRI64 = {}
ir_node.extended(impls.IRNodeBSHRI64, ir_node.ir_node_base)

function impls.IRNodeBSHRI64:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_i64_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_i64_op(self:get_right_op(), ctx, type)
    local data = ('(bvlshr %s %s)'):format(left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), type, data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
