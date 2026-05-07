local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeNEWREFP32 = {}
ir_node.extended(impls.IRNodeNEWREFP32, ir_node.ir_node_base)

function impls.IRNodeNEWREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local id = ir_node.retrieve_raw_val(right_op, ctx)
    id = arith_utils.normalize_table_key(id)
    local ssa_ref = self:get_ssa_reference()
    local tab_ssa = left_op:get_ssa()
    if ctx.const_tabs[tab_ssa] == nil then
        ctx.const_tabs[tab_ssa] = {content = {}}
    end
    ctx.const_tabs[ssa_ref] = ctx.const_tabs[tab_ssa]
    if right_op:is_str() then
        ctx.href_keys[ssa_ref] = right_op:get_str()
    end
    local tab_id = ctx.op_stack:load(left_op:get_ssa(), op_type.TAB)
    local p32 = ir_node.make_tab_ref(tab_id, id)
    return ctx.op_stack:store(ssa_ref, op_type.ANY, p32)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
