local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeALOADNum = {}
ir_node.extended(impls.IRNodeALOADNum, ir_node.ir_node_base)

function impls.IRNodeALOADNum:to_smt_lib(ctx)
    local left_op = self:get_left_op()

    local dst_slot = left_op.value

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_i64_op(left_op, ctx, 'i64')
    idx_left = ('(bv2int %s)'):format(idx_left)

    local ssa_ref = self:get_ssa_reference()
    assert(tab_left ~= nil, dst_slot)
    return ('%s\n%s'):format(
        -- I suppose guard for ALOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, 'i64', ctx.mem_stack:load_index(
            tab_left, idx_left)
        )
    )
end

impls.IRNodeALOADTab = {}
ir_node.extended(impls.IRNodeALOADTab, ir_node.ir_node_base)

function impls.IRNodeALOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()

    local dst_slot = left_op.value

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_i64_op(left_op, ctx, 'i64')
    idx_left = ('(bv2int %s)'):format(idx_left)

    assert(tab_left ~= nil, dst_slot)
    local tab_ptr = ctx.mem_stack:load_index(tab_left, idx_left)

    local ssa_ref = self:get_ssa_reference()
    ctx.tab_info[ssa_ref] = {mem_ref = ('(bv2int %s)'):format(tab_ptr)}
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, 'i64', tab_ptr)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
