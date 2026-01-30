local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeSLOADNum = {}
ir_node.extended(impls.IRNodeSLOADNum, ir_node.ir_node_base)

function impls.IRNodeSLOADNum:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op(), ctx)
    local data = ctx.vm_stack:load(slot, self:get_type())
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, self:get_type(), data)
    )
end

impls.IRNodeSLOADInt = {}
ir_node.extended(impls.IRNodeSLOADInt, ir_node.ir_node_base)

function impls.IRNodeSLOADInt:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local data = ctx.vm_stack:load(slot, self:get_type())
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, self:get_type(), data)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
