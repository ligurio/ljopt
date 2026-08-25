-- GC write barriers: TBAR (table), OBAR (object), XBAR (a fence
-- the optimizer may not move loads and stores across).
--
-- None of them changes a value the trace computes -- they exist
-- to keep the collector's invariants while it runs incrementally
-- -- so there is nothing to translate. They are modelled rather
-- than left NYI only so a barrier does not drag the store it
-- guards out of the encoding with it.
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeBarrier = {}
ir_node.extended(IRNodeBarrier, ir_node.ir_node_base)

function IRNodeBarrier:to_smt_lib(ctx)
    return ctx.te_stack:store(self:get_ssa_reference(), 'true')
end

-- A barrier carries no value, so its IR type says nothing about
-- what to emit: TBAR shows up as both `nil` and `tab`. This
-- module is registered only for the three barriers, so whatever
-- type variant arrives is one of them.
local function instance(_node_str)
    return IRNodeBarrier
end

return {
    instance = instance
}
