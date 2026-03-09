local arith_utils = require('ljopt.ir.arith_utils')
local op_type = require('ljopt.ir.op_type')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeAREFP32 = {}
ir_node.extended(impls.IRNodeAREFP32, ir_node.ir_node_base)

function impls.IRNodeAREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local id
    if right_op ~= nil and right_op:is_str() then
        -- Drop @0 etc
        local s = right_op:get_str():gsub('^([^"]*"[^"]*").*', '%1')
        id = arith_utils.const_str_to_memcell(s)
    else
        id = ir_node.retrieve_raw_val(right_op, ctx)
        id = arith_utils.normalize_table_key(id)
    end
    local ssa_ref = self:get_ssa_reference()
    ctx.tab_info[ssa_ref] = ctx.tab_info[left_op:get_ssa()]
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.ANY, id)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
