-- Writes the upvalue a UREF names -- HSTORE on the closure.
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeUSTORENum = {}
ir_node.extended(impls.IRNodeUSTORENum, ir_node.ir_node_base)

function impls.IRNodeUSTORENum:to_smt_lib(ctx)
    local tab_left, idx_left =
        ir_node.retrieve_tab_ref(self:get_left_op(), ctx)
    local value = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, op_type.NUM
    )
    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.NUM)
end

impls.IRNodeUSTOREStr = {}
ir_node.extended(impls.IRNodeUSTOREStr, ir_node.ir_node_base)

function impls.IRNodeUSTOREStr:to_smt_lib(ctx)
    local tab_left, idx_left =
        ir_node.retrieve_tab_ref(self:get_left_op(), ctx)
    local value = ir_node.retrieve_str_op(self:get_right_op(), ctx)
    return ctx.mem_stack:store_index(tab_left, idx_left, value, op_type.STR)
end

-- The stored table becomes reachable through the upvalue, so its
-- id has to line up with its counterpart on the other side.
impls.IRNodeUSTORETab = {}
ir_node.extended(impls.IRNodeUSTORETab, ir_node.ir_node_base)

function impls.IRNodeUSTORETab:to_smt_lib(ctx)
    local src_slot = self:get_right_op():get_ssa()
    local tab_left, idx_left =
        ir_node.retrieve_tab_ref(self:get_left_op(), ctx)
    local src_tab = ctx.op_stack:load(src_slot, op_type.TAB)
    ctx.mem_stack:mark_escaped(src_slot)
    return ctx.mem_stack:store_index(tab_left, idx_left, src_tab, op_type.TAB)
end

impls.IRNodeUSTORE = {}
ir_node.extended(impls.IRNodeUSTORE, ir_node.ir_node_base)

function impls.IRNodeUSTORE:to_smt_lib(ctx)
    local tab_left, idx_left =
        ir_node.retrieve_tab_ref(self:get_left_op(), ctx)
    return ctx.mem_stack:store_index(tab_left, idx_left, nil, op_type.NIL)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
