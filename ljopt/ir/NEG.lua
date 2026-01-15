local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeNEGBase = {}
ir_node.extended(IRNodeNEGBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeNEGInt = {}
ir_node.extended(impls.IRNodeNEGInt, IRNodeNEGBase)

function impls.IRNodeNEGInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local data = string.format('(bvneg %s)', left_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeNEGNum = {}
ir_node.extended(impls.IRNodeNEGNum, IRNodeNEGBase)

function impls.IRNodeNEGNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local data = string.format('(fp.neg %s)', left_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
