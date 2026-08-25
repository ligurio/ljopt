local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeFSTORETab = {}
ir_node.extended(impls.IRNodeFSTORETab, ir_node.ir_node_base)

-- `FSTORE <fref>, <tab>` -- what setmetatable() lowers to.
--
-- The destination is an FREF, so it names one field rather than
-- an object: decode the reference and write that cell, the way
-- HSTORE writes the cell an HREFK names. The table being stored
-- becomes reachable through the field, so its id has to line up
-- with its counterpart -- hence mark_escaped().
function impls.IRNodeFSTORETab:to_smt_lib(ctx)
    local src_slot = self:get_right_op():get_ssa()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(self:get_left_op(), ctx)
    local src_tab = ctx.op_stack:load(src_slot, op_type.TAB)
    ctx.mem_stack:mark_escaped(src_slot)
    return ctx.mem_stack:store_index(tab_left, idx_left, src_tab, op_type.TAB)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
