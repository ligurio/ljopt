local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeBANDBase = {}
ir_node.extended(IRNodeBANDBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeBROLI64 = {}
ir_node.extended(impls.IRNodeBROLI64, IRNodeBANDBase)

function impls.IRNodeBROLI64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format('(ext_rotate_left %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
