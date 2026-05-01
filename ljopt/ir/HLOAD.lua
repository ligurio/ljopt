local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeHLOADStr = {}
ir_node.extended(impls.IRNodeHLOADStr, ir_node.ir_node_base)

function impls.IRNodeHLOADStr:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local tab_left, idx_left, raw_cell = ir_node.retrieve_tab_ref(left_op, ctx)

    local ssa_ref = self:get_ssa_reference()

    local dst_slot = left_op:get_ssa()
    local key = ctx.href_keys[dst_slot]
    local ct = ctx.const_tabs[dst_slot]
    if key ~= nil and ct ~= nil and ct.content[key] ~= nil then
        ctx.const_strs[ssa_ref] = ct.content[key]
    end

    return ('(assert ((_ is str-val) %s))\n%s\n%s'):format(
        raw_cell,
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.STR,
            ctx.mem_stack:load_index(tab_left, idx_left, op_type.STR)
        )
    )
end

impls.IRNodeHLOADNum = {}
ir_node.extended(impls.IRNodeHLOADNum, ir_node.ir_node_base)

function impls.IRNodeHLOADNum:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local tab_left, idx_left, raw_cell = ir_node.retrieve_tab_ref(left_op, ctx)

    local ssa_ref = self:get_ssa_reference()
    local dst_slot = left_op:get_ssa()
    local key = ctx.href_keys[dst_slot]
    local ct = ctx.const_tabs[dst_slot]
    if key ~= nil and ct ~= nil and ct.content[key] ~= nil then
        ctx.const_nums[ssa_ref] = ct.content[key]
    end
    local te_guard = ('((_ is fp-val) %s)'):format(raw_cell)
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, te_guard),
        ctx.op_stack:store(ssa_ref, op_type.NUM, ctx.mem_stack:load_index(
            tab_left, idx_left, op_type.NUM)
        )
    )
end

impls.IRNodeHLOADTab = {}
ir_node.extended(impls.IRNodeHLOADTab, ir_node.ir_node_base)

function impls.IRNodeHLOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local _, _, raw_cell = ir_node.retrieve_tab_ref(left_op, ctx)

    local ssa_ref = self:get_ssa_reference()
    local tab_id = ir_node.get_table_uid(raw_cell, ctx.mem_stack:alloc_slot())
    return ('(assert ((_ is tab-val) %s))\n%s\n%s'):format(
        raw_cell,
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.TAB, tab_id)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
