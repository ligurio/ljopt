local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeHREFKP32 = {}
ir_node.extended(impls.IRNodeHREFKP32, ir_node.ir_node_base)

function impls.IRNodeHREFKP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local id
    if right_op:is_str() then
        id = arith_utils.const_int_to_smt_bv(
            tonumber(utils.hash(right_op:get_str()))
        )
    elseif right_op:is_num() then
        id = arith_utils.const_int_to_smt_bv(right_op:get_num())
    else
        id = ir_node.retrieve_i64_op(right_op, ctx, 'i64')
    end
    local ssa_ref = self:get_ssa_reference()
    ctx.tab_info[ssa_ref] = ctx.tab_info[left_op:get_ssa()]
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, self:get_type(), id)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
