local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

-- ldexp(x, n) = x * 2^n. Encoded purely in FP via smt_ldexp in
-- smt_constants.lua (fp.mul with a 2^n FP constant built from
-- n's biased exponent).
impls.IRNodeLDEXPNum = {}
ir_node.extended(impls.IRNodeLDEXPNum, bin_op.BinOpNum)

function impls.IRNodeLDEXPNum:to_smt_lib(ctx)
    local ssa_ref = self:get_ssa_reference()
    local type = self:get_type()
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, type
    )
    local right_op = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, type
    )

    local lc = utils.resolve_const(self:get_left_op(), ctx)
    local rc = utils.resolve_const(self:get_right_op(), ctx)
    if lc ~= nil and rc ~= nil then
        ctx.const_nums[ssa_ref] = math.ldexp(lc, rc)
    end

    local data = ('(smt_ldexp %s %s)'):format(left_op, right_op)
    return ctx.op_stack:store(ssa_ref, type, data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance,
}
