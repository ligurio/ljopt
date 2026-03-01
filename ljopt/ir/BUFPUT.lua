local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')
local bit = require('bit')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeBUFPUTP32 = {}
ir_node.extended(impls.IRNodeBUFPUTP32, ir_node.ir_node_base)

function impls.IRNodeBUFPUTP32:to_smt_lib(ctx)
    local ref = self:get_left_op()
    assert(ref:is_ssa(), ref.kind)
    local mode = self:get_right_op()
    local str = nil
    if mode:is_str() then
        str = '"' .. mode.value .. '"'
    elseif mode:is_ssa() then
        local slot = ctx.tab_info[mode.value].mem_ref
        str = ctx.string_stack:load(slot)
    else
        utils.unreachable(mode.kind)
    end
    local ssa_ref = self:get_ssa_reference()
    local idx = ctx.tab_info[ref.value].mem_ref
    ctx.tab_info[ssa_ref] = {mem_ref = idx, meta = nil}
    return ('%s'):format(
        ctx.string_stack:append(idx, str)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
