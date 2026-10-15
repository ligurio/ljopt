local arith_utils = require('ljopt.ir.arith_utils')
local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSHLI64 = { op_str = 'bvshl' }
ir_node.extended(impls.IRNodeBSHLI64, bin_op.BinOpI64)

-- 32-bit left shift (bit.lshift). The count is masked to 5 bits
-- and the shift runs on the low 32 bits of the sign-extended cell
-- (a bare bvshl on the 64-bit value is wrong once the count is
-- >= 32 and the value is negative).
impls.IRNodeBSHLInt = {}
ir_node.extended(impls.IRNodeBSHLInt, ir_node.ir_node_base)

function impls.IRNodeBSHLInt:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, type)
    local data = arith_utils.bv_shift32('bvshl', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), type, data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
