local ffi = require('ffi')

local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeHSTOREStr = {}
ir_node.extended(impls.IRNodeHSTOREStr, ir_node.ir_node_base)

function impls.IRNodeHSTOREStr:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local dst_slot = tonumber(left_op)
    local src_slot = tonumber(right_op)

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_i64_op(left_op, ctx, 'i64')
    idx_left = ('(bv2int %s)'):format(idx_left)
    if right_op ~= nil and string.sub(right_op, 1, 1) == '"' then
        value = arith_utils.const_to_smt_bv(0)
        -- value = arith_utils.const_to_smt_bv(tonumber(utils.hash(right_op)))
    else
        value = ir_node.retrieve_i64_op(right_op, ctx, 'i64')
    end

    assert(tab_left ~= nil, dst_slot)

    return ctx.mem_stack:store_index(tab_left, idx_left, value)
end

impls.IRNodeHSTORENum = {}
ir_node.extended(impls.IRNodeHSTORENum, ir_node.ir_node_base)

function impls.IRNodeHSTORENum:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local dst_slot = tonumber(left_op)
    local src_slot = tonumber(right_op)

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_i64_op(left_op, ctx, 'i64')
    idx_left = ('(bv2int %s)'):format(idx_left)
    if right_op ~= nil and string.sub(right_op, 1, 1) == '"' then
        value = arith_utils.const_to_smt_bv(tonumber(utils.hash(right_op)))
    else
        value = ir_node.retrieve_i64_op(right_op, ctx, 'i64')
    end

    assert(tab_left ~= nil, dst_slot)

    return ctx.mem_stack:store_index(tab_left, idx_left, value)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
