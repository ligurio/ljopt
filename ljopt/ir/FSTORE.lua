local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeFSTORETab = {}
ir_node.extended(impls.IRNodeFSTORETab, ir_node.ir_node_base)

-- 0027    tab FSTORE 0026  0018
-- where 0026 is `p32 FREF 0002 tab.meta`.
-- 1. Decode the FREF address (table pointer + field index)
--    produced by IRNodeFREFP32.
-- 2. Load the table uid stored in the source operand.
-- 3. Write the table uid to the addressed field of the table.
function impls.IRNodeFSTORETab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local src_slot = right_op:get_ssa()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    local src_tab = ctx.op_stack:load(src_slot, op_type.TAB)
    return ctx.mem_stack:store_index(tab_left, idx_left, src_tab, op_type.TAB)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
