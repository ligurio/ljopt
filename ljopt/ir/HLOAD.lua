local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeHLOADStr = {}
ir_node.extended(impls.IRNodeHLOADStr, ir_node.ir_node_base)

function impls.IRNodeHLOADStr:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local dst_slot = left_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_i64_op(left_op, ctx, 'i64')
    idx_left = ('(bv2int %s)'):format(idx_left)
    local value
    if right_op ~= nil and right_op:is_str() then
        local hash = utils.hash(right_op:get_str())
        value = arith_utils.const_num_to_smt_bv(
            tonumber(hash)
        )
    else
        value = ir_node.retrieve_i64_op(right_op, ctx, 'i64')
    end

    assert(tab_left ~= nil, dst_slot)

    return ctx.mem_stack:load_index(tab_left, idx_left, value)
end

impls.IRNodeHLOADNum = {}
ir_node.extended(impls.IRNodeHLOADNum, ir_node.ir_node_base)

function impls.IRNodeHLOADNum:to_smt_lib(ctx)
    local left_op = self:get_left_op()

    local dst_slot = left_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_i64_op(left_op, ctx, 'i64')
    idx_left = ('(bv2int %s)'):format(idx_left)

    local ssa_ref = self:get_ssa_reference()
    assert(tab_left ~= nil, dst_slot)
    return ('%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, 'i64', ctx.mem_stack:load_index(
            tab_left, idx_left)
        )
    )
end

impls.IRNodeHLOADTab = {}
ir_node.extended(impls.IRNodeHLOADTab, ir_node.ir_node_base)

function impls.IRNodeHLOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()

    local dst_slot = left_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_i64_op(left_op, ctx, 'i64')
    idx_left = ('(bv2int %s)'):format(idx_left)

    local tab_ptr = ctx.mem_stack:load_index(tab_left, idx_left)

    local ssa_ref = self:get_ssa_reference()
    ctx.tab_info[ssa_ref] = {mem_ref = ('(bv2int %s)'):format(tab_ptr)}
    assert(tab_left ~= nil, dst_slot)
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
