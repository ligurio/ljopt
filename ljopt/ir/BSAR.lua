local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

-- 32-bit arithmetic shift right (bit.arshift). The count is
-- masked to 5 bits and the shift runs on the low 32 bits of the
-- sign-extended cell.
impls.IRNodeBSARInt = {}
ir_node.extended(impls.IRNodeBSARInt, ir_node.ir_node_base)

function impls.IRNodeBSARInt:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, type)
    local data = arith_utils.bv_shift32('bvashr', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), type, data)
end

impls.IRNodeBSARI64 = { op_str = 'bvashr' }
ir_node.extended(impls.IRNodeBSARI64, ir_node.ir_node_base)

function impls.IRNodeBSARI64:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_i64_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_i64_op(self:get_right_op(), ctx, type)
    local data = ('(bvashr %s %s)'):format(left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), type, data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
