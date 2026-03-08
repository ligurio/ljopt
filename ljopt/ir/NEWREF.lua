local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeNEWREFP32 = {}
ir_node.extended(impls.IRNodeNEWREFP32, ir_node.ir_node_base)

function impls.IRNodeNEWREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local id = ir_node.retrieve_raw_val(right_op, ctx)
    ctx.tab_info[self:get_ssa_reference()] = ctx.tab_info[left_op:get_ssa()]
    return ctx.op_stack:store(self:get_ssa_reference(), op_type.ANY, id)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
