local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBROLInt = {}
ir_node.extended(impls.IRNodeBROLInt, ir_node.ir_node_base)

function impls.IRNodeBROLInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, self:get_type())
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, self:get_type())
    local left_i32 = ('((_ extract 31 0) %s)'):format(left_op)
    local right_i32 = ('((_ extract 31 0) %s)'):format(right_op)
    local data = ('(concat #x00000000 (ext_rotate_left %s %s))'):format(
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
