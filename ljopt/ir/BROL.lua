local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')

local impls = {}

impls.IRNodeBROLInt = {}
ir_node.extended(impls.IRNodeBROLInt, ir_node.ir_node_base)

function impls.IRNodeBROLInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_int_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local left_i32 = ('((_ extract 31 0) %s)'):format(left_op)
    local right_i32 = ('((_ extract 31 0) %s)'):format(right_op)
    local rotated = arith_utils.brol32(left_i32, right_i32)
    -- Sign-extend, not zero-extend: int values are held in the
    -- op stack in sign-extended 64-bit form (see BSWAP and the
    -- int.i64 CONV), so a rotate result with the top bit set
    -- would otherwise disagree with every other int op -- and
    -- with BROR, which already sign-extends.
    local data = ('((_ sign_extend 32) %s)'):format(rotated)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeBROLI64 = {}
ir_node.extended(impls.IRNodeBROLI64, ir_node.ir_node_base)

function impls.IRNodeBROLI64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_int_op(
        self:get_right_op(), ctx, self:get_type()
    )

    -- For 64-bit rotate left, we need the full
    -- 64-bit values.
    local left_i64 = left_op
    local right_i64 = right_op

    -- Extract the lower 6 bits for shift amount
    -- (bits 5-0, since 2^6 = 64).
    -- BROL is done by modulos 64.
    local shift_amount = ('((_ extract 5 0) %s)'):format(right_i64)
    shift_amount = ('((_ zero_extend 58) %s)'):format(shift_amount)
    -- Implement 64-bit rotate left using SMT-LIB
    -- (x << (shift % 64)) | (x >> (64 - (shift % 64)))
    local fmt = '(bvor (bvshl %s %s) (bvlshr %s (bvsub #x0000000000000040 %s)))'
    local rotated = fmt:format(
        left_i64, shift_amount, left_i64, shift_amount
    )

    return ctx.op_stack:store(
        self:get_ssa_reference(), self:get_type(),
        rotated
    )
end

-- u64 rotates at the same 64-bit width as i64, and the rotate is
-- bit-pattern-only, so signedness never enters into it.
impls.IRNodeBROLU64 = {}
ir_node.extended(impls.IRNodeBROLU64, impls.IRNodeBROLI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
