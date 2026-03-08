local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeALOADNum = {}
ir_node.extended(impls.IRNodeALOADNum, ir_node.ir_node_base)

function impls.IRNodeALOADNum:to_smt_lib(ctx)
    local left_op = self:get_left_op()

    local dst_slot = left_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_raw_val(left_op, ctx)

    local ssa_ref = self:get_ssa_reference()
    assert(tab_left ~= nil, dst_slot)
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.NUM,
            ctx.mem_stack:load_index(tab_left, idx_left, op_type.NUM)
        )
    )
end

impls.IRNodeALOADTab = {}
ir_node.extended(impls.IRNodeALOADTab, ir_node.ir_node_base)

function impls.IRNodeALOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()

    local dst_slot = left_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_raw_val(left_op, ctx)

    assert(tab_left ~= nil, dst_slot)
    local tab_ptr = ctx.mem_stack:load_index(tab_left, idx_left, op_type.TAB)

    local ssa_ref = self:get_ssa_reference()
    ctx.tab_info[ssa_ref] = {mem_ref = ('(bv2int %s)'):format(tab_ptr)}
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.TAB, tab_ptr)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
