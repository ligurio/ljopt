local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeSUBNum = {
    op_str = 'fp.sub',
    const_fn = function(a, b) return a - b end
}
ir_node.extended(impls.IRNodeSUBNum, bin_op.BinOpNum)
impls.IRNodeSUBInt = {
    op_str = 'bvsub',
    const_fn = function(a, b) return a - b end
}
ir_node.extended(impls.IRNodeSUBInt, bin_op.BinOpInt)
impls.IRNodeSUBI64 = { op_str = 'bvsub' }
ir_node.extended(impls.IRNodeSUBI64, bin_op.BinOpI64)

impls.IRNodeSUBU32 = { op_str = 'bvsub' }
ir_node.extended(impls.IRNodeSUBU32, bin_op.BinOpU32)

-- `SUB REF_BASE, framesize` is not arithmetic to model: it is
-- how the recorder names the base of the vararg region, and
-- REF_BASE has no value on the op stack to subtract from. Both
-- traces mean the same region, so it resolves to one shared
-- object rather than to two unconstrained reads.
local sub_int_to_smt_lib = impls.IRNodeSUBInt.to_smt_lib

function impls.IRNodeSUBInt:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    if left_op ~= nil and left_op:is_ssa() and left_op:get_ssa() == 0 then
        local ssa_ref = self:get_ssa_reference()
        ctx.vararg_refs[ssa_ref] = true
        local slot = ctx.mem_stack:allocate(constants.VARARG_SLOT)
        return ctx.op_stack:store(ssa_ref, op_type.TAB, tostring(slot))
    end
    return sub_int_to_smt_lib(self, ctx)
end
impls.IRNodeSUBU64 = { op_str = 'bvsub' }
ir_node.extended(impls.IRNodeSUBU64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
