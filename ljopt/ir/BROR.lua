local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBRORInt = {}
ir_node.extended(impls.IRNodeBRORInt, ir_node.ir_node_base)

function impls.IRNodeBRORInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local left_i32 = ('((_ extract 31 0) %s)'):format(left_op)
    local right_i32 = ('((_ extract 31 0) %s)'):format(right_op)
    local data = ('(concat #x00000000 (ext_rotate_right %s %s))'):format(
        left_i32, right_i32
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
