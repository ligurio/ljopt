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

impls.IRNodeSLOADTab = {}
ir_node.extended(impls.IRNodeSLOADTab, ir_node.ir_node_base)

function impls.IRNodeSLOADTab:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local ssa_ref = self:get_ssa_reference()
    local mem_slot, smt_fm = ctx.mem_stack:allocate(slot)
    assert(ctx.tab_info[ssa_ref] == nil, 'We already wrote here? Weird ' .. ssa_ref)
    ctx.tab_info[ssa_ref] = {mem_ref = mem_slot, shared_base = slot, shared_depth = 0}
    return ('%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        smt_fm
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
