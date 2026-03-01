local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeXLOADU16 = {}
ir_node.extended(impls.IRNodeXLOADU16, ir_node.ir_node_base)

function impls.IRNodeXLOADU16:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    assert(left_op:is_ssa())

    local dst_slot = left_op.value

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
        ctx.op_stack:store(ssa_ref, 'u16', ctx.mem_stack:load_index(
            tab_left, idx_left)
        )
    )
end

impls.IRNodeXLOADU8 = {}
ir_node.extended(impls.IRNodeXLOADU8, ir_node.ir_node_base)

function impls.IRNodeXLOADU8:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    assert(left_op:is_ssa())

    local dst_slot = left_op.value

    -- Table pointer. Compile time.
    print(dst_slot)
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
        ctx.op_stack:store(ssa_ref, 'u8', ctx.mem_stack:load_index(
            tab_left, idx_left)
        )
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
