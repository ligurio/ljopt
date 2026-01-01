local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeSUBOVBase = {}
ir_node.extended(IRNodeSUBOVBase, ir_node.ir_node_base)

local impls = {}



impls.IRNodeSUBOVInt = {}
ir_node.extended(impls.IRNodeSUBOVInt, IRNodeSUBOVBase)

function impls.IRNodeSUBOVInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvsub %s %s)', left_op, right_op)
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, arith_utils.i32_overflow_check(data)),
        ctx.op_stack:store(ssa_ref, self:get_type(), data)
    )
end

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'SUBOV', left_op, right_op
    )
    return node
end

return {
    instance = instance
}
