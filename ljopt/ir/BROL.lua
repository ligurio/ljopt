local ir_node = require('ljopt.ir.ir_node_base')

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
    local data = ('(concat #x00000000 (ext_rotate_left %s %s))'):format(
        left_i32, right_i32
    )
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
    
    -- For 64-bit rotate left, we need the full 64-bit values
    local left_i64 = left_op
    local right_i64 = right_op
    
    -- Extract the lower 6 bits for shift amount (bits 5-0, since 2^6 = 64)
    -- BROL is done by modulos 64.
    local shift_amount = ('((_ extract 5 0) %s)'):format(right_i64)
    
    -- Implement 64-bit rotate left using SMT-LIB
    -- (x << shift) | (x >> (64 - shift))
    -- Need to handle shift = 0 case carefully
    local rotated = ('(bvor (bvshl %s %s) (bvlshr %s (bvsub #x0000000000000040 %s)))'):format(
        left_i64, shift_amount, left_i64, shift_amount
    )
    
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), rotated)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
