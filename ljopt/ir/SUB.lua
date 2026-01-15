local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeSUBBase = {}
ir_node.extended(IRNodeSUBBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeSUBNum = {}
ir_node.extended(impls.IRNodeSUBNum, IRNodeSUBBase)

function impls.IRNodeSUBNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(fp.sub RNE %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeSUBInt = {}
ir_node.extended(impls.IRNodeSUBInt, IRNodeSUBBase)

function impls.IRNodeSUBInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvsub %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
