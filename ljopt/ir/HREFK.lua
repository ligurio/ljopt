local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeHREFKP32 = {}
ir_node.extended(impls.IRNodeHREFKP32, ir_node.ir_node_base)

function impls.IRNodeHREFKP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local right_op_str = ir_node.OpKind.to_string(right_op)
    local id
    local constant, _ = right_op_str:match("^(%S+)%s+(%S+)")
    if string.sub(constant, 1, 1) == '"' then
        id = arith_utils.const_int_to_smt_bv(tonumber(utils.hash(constant)))
    elseif string.sub(constant, 1, 1) == '#' then
        -- Already SMT format
        id = constant
    else
        id = ir_node.retrieve_i64_op(right_op, ctx, 'i64')
    end
    local ssa_ref = self:get_ssa_reference()
    ctx.tab_info[ssa_ref] = ctx.tab_info[left_op.value]
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
