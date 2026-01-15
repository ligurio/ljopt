local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeMULBase = {}
ir_node.extended(IRNodeMULBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeMULNum = {}
ir_node.extended(impls.IRNodeMULNum, IRNodeMULBase)

function impls.IRNodeMULNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(fp.mul RNE %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeMULInt = {}
ir_node.extended(impls.IRNodeMULInt, IRNodeMULBase)

function impls.IRNodeMULInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvmul %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
