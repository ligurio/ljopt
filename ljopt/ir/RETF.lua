-- The guard on a return into a lower frame: the trace checks it
-- is returning where it was recorded returning.
--
-- Which frame that is depends on how the trace was entered, not
-- on anything the encoding models -- both sides were recorded
-- from the same call, so both would check the same thing. It is
-- translated as a guard that holds rather than left NYI, because
-- an unimplemented node takes the whole return path down with
-- it. The cost is that a RETF the optimizer dropped on one side
-- only is not visible here.
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeRETF = {}
ir_node.extended(IRNodeRETF, ir_node.ir_node_base)

function IRNodeRETF:to_smt_lib(ctx)
    return ctx.te_stack:store(self:get_ssa_reference(), 'true')
end

local function instance(_node_str)
    return IRNodeRETF
end

return {
    instance = instance
}
