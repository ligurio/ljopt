local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeHSTOREStr = {}
ir_node.extended(impls.IRNodeHSTOREStr, ir_node.ir_node_base)

function impls.IRNodeHSTOREStr:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local dst_slot = left_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_raw_val(left_op, ctx)
    local value = ir_node.retrieve_str_op(right_op, ctx)

    assert(value ~= nil)
    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.STR)
end

impls.IRNodeHSTORENum = {}
ir_node.extended(impls.IRNodeHSTORENum, ir_node.ir_node_base)

function impls.IRNodeHSTORENum:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local dst_slot = left_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_raw_val(left_op, ctx)
    local value = ir_node.retrieve_num_op(right_op, ctx, op_type.NUM)

    assert(tab_left ~= nil, dst_slot)

    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.NUM)
end

impls.IRNodeHSTORETab = {}
ir_node.extended(impls.IRNodeHSTORETab, ir_node.ir_node_base)

-- 0019    tab HSTORE 0016  0004
-- 1. Get reference at 0019.
-- 2. Get table uid at 0004.
-- 3. Write table_uid to ref (and add some string
-- to avoid hash collisions with left table metadata).
function impls.IRNodeHSTORETab:to_smt_lib(ctx)
    -- Assume it's a stack slot, like `0001`.
    local left_op = self:get_left_op()

    local right_op = self:get_right_op()

    local dst_slot = left_op:get_ssa()
    local src_slot = right_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_right = ctx.mem_stack:key_id(src_slot)
    idx_right = arith_utils.const_int_to_smt_bv(idx_right)
    local idx_left = ir_node.retrieve_raw_val(left_op, ctx)
    return ctx.mem_stack:store_index(tab_left, idx_left, idx_right, op_type.I64)
end

impls.IRNodeHSTORE = {}
ir_node.extended(impls.IRNodeHSTORE, ir_node.ir_node_base)

function impls.IRNodeHSTORE:to_smt_lib(ctx)
    local left_op = self:get_left_op()

    local dst_slot = left_op:get_ssa()

    -- Table pointer. Compile time.
    local tab_left = ctx.tab_info[dst_slot].mem_ref
    -- Table index. Runtime.
    local idx_left = ir_node.retrieve_raw_val(left_op, ctx)
    -- Nil sentinel value.
    local value = '#x0000000000000000'

    assert(tab_left ~= nil, dst_slot)
    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.I64)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
