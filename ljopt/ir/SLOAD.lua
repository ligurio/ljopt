local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeSLOAD = {}
ir_node.extended(IRNodeSLOAD, ir_node.ir_node_base)

function IRNodeSLOAD:to_smt_lib(ctx)
    local slot = self:retrieve_slot_op(self:get_left_op(), ctx)
    local data = ctx.vm_stack:load(slot, self:get_type())
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, self:get_type(), data)
    )
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeSLOAD:new(ssa_ref, flags, type, 'SLOAD', left_op, right_op)
end

return {
    instance = instance
}
