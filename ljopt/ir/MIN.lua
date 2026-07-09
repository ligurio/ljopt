local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

-- LuaJIT's IR_MIN is deterministic `x < y ? x : y`
-- (lj_vm_foldarith / minsd), NOT SMT `fp.min` which is
-- unspecified on +0/-0 inputs (z3 may return -0.0 for
-- min(-0.0,+0.0) while the fold picks +0.0 -- spurious sat).
-- Model the exact comparison instead. The const_fn mirrors it
-- so ljopt-side folding agrees.
impls.IRNodeMINNum = {
    const_fn = function(a, b) return a < b and a or b end,
}
ir_node.extended(impls.IRNodeMINNum, bin_op.BinOpNum)

function impls.IRNodeMINNum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, self:get_type()
    )
    if self.const_fn then
        local lc = require('ljopt.utils').resolve_const(self:get_left_op(), ctx)
        local rc = require('ljopt.utils').resolve_const(
            self:get_right_op(), ctx
        )
        if lc ~= nil and rc ~= nil then
            ctx.const_nums[self:get_ssa_reference()] = self.const_fn(lc, rc)
        end
    end
    local data = string.format('(ite (fp.lt %s %s) %s %s)',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeMINInt = {}
ir_node.extended(impls.IRNodeMINInt, bin_op.BinOpInt)

function impls.IRNodeMINInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_int_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(ite (bvsle %s %s) %s %s)',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
