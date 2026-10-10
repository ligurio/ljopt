local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

-- BSHR is the *logical* shift right (bit.rshift): zero bits
-- shift in. Shifts are defined modulo 32, so the count is masked
-- to 5 bits and the shift runs on the low 32 bits (a bare
-- arithmetic 64-bit shift would replicate the sign and a count
-- >= 32 would be wrong).
impls.IRNodeBSHRInt = {}
ir_node.extended(impls.IRNodeBSHRInt, ir_node.ir_node_base)

function impls.IRNodeBSHRInt:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, type)
    local data = arith_utils.bv_shift32('bvlshr', left_op, right_op)
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
