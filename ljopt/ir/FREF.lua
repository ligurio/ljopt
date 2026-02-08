local ffi = require('ffi')

local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeFREFP32 = {}
ir_node.extended(impls.IRNodeFREFP32, ir_node.ir_node_base)

function impls.IRNodeFREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    if right_op == 'tab.meta' then
        local metatable = ctx.metatab_info[ctx.tab_info[tonumber(left_op)].mem_ref].mt_ref
        ctx.tab_info[self:get_ssa_reference()] = {
            mem_ref = metatable
        }
    else
        assert(false, right_op)
    end
    return '; Nothing to do'
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
