local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeADDBase = {}
ir_node.extended(IRNodeADDBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeADDNum = {}
ir_node.extended(impls.IRNodeADDNum, IRNodeADDBase)

function impls.IRNodeADDNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(fp.add RNE %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeADDInt = {}
ir_node.extended(impls.IRNodeADDInt, IRNodeADDBase)

function impls.IRNodeADDInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvadd %s %s)', left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
