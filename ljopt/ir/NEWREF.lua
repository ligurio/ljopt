local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeNEWREFP32 = {}
ir_node.extended(impls.IRNodeNEWREFP32, ir_node.ir_node_base)

function impls.IRNodeNEWREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local right_op_str = ir_node.OpKind.to_string(right_op)
    local id
    if right_op ~= nil and right_op:is_str() then
        id = arith_utils.const_int_to_smt_bv(tonumber(utils.hash(right_op_str)))
    else
        id = ir_node.retrieve_i64_op(right_op, ctx, 'i64')
    end
    ctx.tab_info[self:get_ssa_reference()] = ctx.tab_info[left_op.value]
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), id)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
