local op_type = require('ljopt.ir.op_type')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeASTOREStr = {}
ir_node.extended(impls.IRNodeASTOREStr, ir_node.ir_node_base)

function impls.IRNodeASTOREStr:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    local value = ir_node.retrieve_str_op(right_op, ctx)

    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.STR)
end

impls.IRNodeASTORENum = {}
ir_node.extended(impls.IRNodeASTORENum, ir_node.ir_node_base)

function impls.IRNodeASTORENum:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    local value = ir_node.retrieve_num_op(right_op, ctx, op_type.NUM)

    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.NUM)
end

impls.IRNodeASTORETab = {}
ir_node.extended(impls.IRNodeASTORETab, ir_node.ir_node_base)

-- 0019    tab ASTORE 0016  0004
-- 1. Get reference at 0019.
-- 2. Get table uid at 0004.
-- 3. Write table_uid to ref (and add some string
-- to avoid hash collisions with left table metadata).
function impls.IRNodeASTORETab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local src_slot = right_op:get_ssa()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    local src_tab = ctx.op_stack:load(src_slot, 'tab')
    return ctx.mem_stack:store_index(tab_left, idx_left, src_tab, op_type.TAB)
end

-- A cdata box (from CNEWI) is referenced the same way a table is:
-- its allocation index is stored as a `tab-val` ref. So storing a
-- cdt into an array mirrors IRNodeASTORETab.
impls.IRNodeASTORECdt = {}
ir_node.extended(impls.IRNodeASTORECdt, ir_node.ir_node_base)

function impls.IRNodeASTORECdt:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local src_slot = right_op:get_ssa()

    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    local src_cdt = ctx.op_stack:load(src_slot, 'tab')
    return ctx.mem_stack:store_index(tab_left, idx_left, src_cdt, op_type.TAB)
end

local function bool_astore_to_smt_lib(self, ctx)
    local left_op = self:get_left_op()
    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    return ctx.mem_stack:store_index(tab_left, idx_left,
        self.hex_constant, op_type.I64)
end

impls.IRNodeASTOREFal = {}
ir_node.extended(impls.IRNodeASTOREFal, ir_node.ir_node_base)
impls.IRNodeASTOREFal.hex_constant = '#xFFFFFFFE00000000'
impls.IRNodeASTOREFal.to_smt_lib = bool_astore_to_smt_lib

impls.IRNodeASTORETru = {}
ir_node.extended(impls.IRNodeASTORETru, ir_node.ir_node_base)
impls.IRNodeASTORETru.hex_constant = '#xFFFFFFFD00000000'
impls.IRNodeASTORETru.to_smt_lib = bool_astore_to_smt_lib

-- ASTORE with no type suffix writes the `nil` sentinel
-- (LuaJIT deletes a slot). Mirrors `IRNodeHSTORE` in HSTORE.lua.
impls.IRNodeASTORE = {}
ir_node.extended(impls.IRNodeASTORE, ir_node.ir_node_base)

function impls.IRNodeASTORE:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)
    -- Nil sentinel value.
    local value = '#x0000000000000000'
    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.I64)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
