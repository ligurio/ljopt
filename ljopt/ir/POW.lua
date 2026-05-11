local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodePOWNum = {
    op_str = 'pow_fp',
    ignore_rounding = true,
    const_fn = function(a, b) return a ^ b end,
}
ir_node.extended(impls.IRNodePOWNum, bin_op.BinOpNum)

-- LuaJIT FOLD rewrites `x ^ 1` to `x` in the optimised trace.
-- `pow_fp` is uninterpreted on the SMT side, so without a
-- matching identity here the unopt-side POW result is
-- unconstrained while opt's folded value is just `x`, and the
-- equivalence check goes spuriously sat. Emit the identity
-- directly when the exponent resolves to a known constant `1`.
function impls.IRNodePOWNum:to_smt_lib(ctx)
    local ssa_ref = self:get_ssa_reference()
    local rc = utils.resolve_const(self:get_right_op(), ctx)
    if rc == 1 then
        -- x^1 = x. Propagate const_nums of the left operand so
        -- downstream HSTORE/HLOAD/DIV/TOSTR can keep
        -- const-folding (otherwise the constant-propagation
        -- chain breaks here and tostr_num stays uninterpreted).
        local lc = utils.resolve_const(self:get_left_op(), ctx)
        if lc ~= nil then
            ctx.const_nums[ssa_ref] = lc
        end
        local left_op = ir_node.retrieve_num_op(
            self:get_left_op(), ctx, self:get_type()
        )
        return ctx.op_stack:store(
            ssa_ref, self:get_type(), left_op
        )
    end
    local lc = utils.resolve_const(self:get_left_op(), ctx)
    if lc == 1 then
        -- 1^x = 1. Stamp const_nums so the propagation chain
        -- stays intact even though `x` is symbolic.
        ctx.const_nums[ssa_ref] = 1
        return ctx.op_stack:store(
            ssa_ref, self:get_type(),
            '((_ to_fp 11 53) #x3ff0000000000000)'
        )
    end
    return bin_op.BinOpNum.to_smt_lib(self, ctx)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance,
}
