local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeNEBase = {}
ir_node.extended(IRNodeNEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeNEInt = {}
ir_node.extended(impls.IRNodeNEInt, IRNodeNEBase)

function impls.IRNodeNEInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(distinct %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

impls.IRNodeNENum = {}
ir_node.extended(impls.IRNodeNENum, IRNodeNEBase)

function impls.IRNodeNENum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(distinct %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
