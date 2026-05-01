local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeHSTOREStr = {}
ir_node.extended(impls.IRNodeHSTOREStr, ir_node.ir_node_base)

function impls.IRNodeHSTOREStr:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local dst_slot = left_op:get_ssa()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    local value = ir_node.retrieve_str_op(right_op, ctx)

    assert(value ~= nil)

    -- Propagate constant string value through table.
    local key = ctx.href_keys[dst_slot]
    local ct = ctx.const_tabs[dst_slot]
    if key ~= nil and ct ~= nil then
        local const_op = utils.resolve_const_str(right_op, ctx)
        if const_op ~= nil then
            ct.content[key] = const_op
        else
            -- Unknown string written: invalidate stale entry so a
            -- subsequent HLOAD doesn't forward the initial-table
            -- value through STRTO/FLOAD const folding.
            ct.content[key] = nil
        end
    end

    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.STR)
end

impls.IRNodeHSTORENum = {}
ir_node.extended(impls.IRNodeHSTORENum, ir_node.ir_node_base)

function impls.IRNodeHSTORENum:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local dst_slot = left_op:get_ssa()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)

    local value = ir_node.retrieve_num_op(right_op, ctx, op_type.NUM)

    -- Propagate constant num value through table.
    local key = ctx.href_keys[dst_slot]
    local ct = ctx.const_tabs[dst_slot]
    if key ~= nil and ct ~= nil then
        local const_op = utils.resolve_const(right_op, ctx)
        if const_op ~= nil then
            ct.content[key] = const_op
        else
            ct.content[key] = nil
        end
    end

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
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local src_slot = right_op:get_ssa()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    local src_tab = ctx.op_stack:load(src_slot, op_type.TAB)
    return ctx.mem_stack:store_index(tab_left, idx_left, src_tab, op_type.TAB)
end

impls.IRNodeHSTORE = {}
ir_node.extended(impls.IRNodeHSTORE, ir_node.ir_node_base)

function impls.IRNodeHSTORE:to_smt_lib(ctx)
    local left_op = self:get_left_op()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    return ctx.mem_stack:store_index(tab_left, idx_left, nil, op_type.NIL)
end

local function bool_hstore_to_smt_lib(self, ctx)
    local left_op = self:get_left_op()
    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    return ctx.mem_stack:store_index(tab_left, idx_left,
        self.hex_constant, op_type.I64)
end

impls.IRNodeHSTOREFal = {}
ir_node.extended(impls.IRNodeHSTOREFal, ir_node.ir_node_base)
impls.IRNodeHSTOREFal.hex_constant = '#xFFFFFFFE00000000'
impls.IRNodeHSTOREFal.to_smt_lib = bool_hstore_to_smt_lib

impls.IRNodeHSTORETru = {}
ir_node.extended(impls.IRNodeHSTORETru, ir_node.ir_node_base)
impls.IRNodeHSTORETru.hex_constant = '#xFFFFFFFD00000000'
impls.IRNodeHSTORETru.to_smt_lib = bool_hstore_to_smt_lib

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
