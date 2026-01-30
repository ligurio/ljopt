local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMULOVInt = {}
ir_node.extended(impls.IRNodeMULOVInt, ir_node.ir_node_base)

function impls.IRNodeMULOVInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_int_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(bvmul %s %s)', left_op, right_op)
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, arith_utils.i32_overflow_check(data)),
        ctx.op_stack:store(ssa_ref, self:get_type(), data)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
