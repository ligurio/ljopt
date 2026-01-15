local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeDIVBase = {}
ir_node.extended(IRNodeDIVBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeDIVNum = {}
ir_node.extended(impls.IRNodeDIVNum, IRNodeDIVBase)

function impls.IRNodeDIVNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(fp.div RNE %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeDIVInt = {}
ir_node.extended(impls.IRNodeDIVInt, IRNodeDIVBase)

function impls.IRNodeDIVInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvsdiv %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
