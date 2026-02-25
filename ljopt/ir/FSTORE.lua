local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeFSTORETab = {}
ir_node.extended(impls.IRNodeFSTORETab, ir_node.ir_node_base)

function impls.IRNodeFSTORETab:to_smt_lib(ctx)
    local dst_slot = self:get_left_op():get_ssa()
    local src_slot = self:get_right_op():get_ssa()

    local tab_left = ctx.tab_info[dst_slot].mem_ref
    assert(tab_left ~= nil, dst_slot)
    local tab_right = ctx.tab_info[src_slot].mem_ref
    assert(tab_right ~= nil, src_slot)

    return ctx.mem_stack:store(tab_left, ctx.mem_stack:load(tab_right))
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
