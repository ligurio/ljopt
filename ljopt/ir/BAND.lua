local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeBANDBase = {}
ir_node.extended(IRNodeBANDBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeBANDInt = {}
ir_node.extended(impls.IRNodeBANDInt, IRNodeBANDBase)

function impls.IRNodeBANDInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvand %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeBANDI64 = {}
ir_node.extended(impls.IRNodeBANDI64, IRNodeBANDBase)

function impls.IRNodeBANDI64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format('(bvand %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
