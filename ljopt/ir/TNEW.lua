local ffi = require('ffi')

local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeTNEWTab = {}
ir_node.extended(impls.IRNodeTNEWTab, ir_node.ir_node_base)

function impls.IRNodeTNEWTab:to_smt_lib(ctx)
    local asize = tonumber(self:get_left_op():sub(2))
    local hsize = tonumber(self:get_right_op():sub(2)) + 1

    local asize_idx = constants.TAB_OFFSETS.asize
    local hsize_idx = constants.TAB_OFFSETS.hmask

    local idx = ctx.mem_stack:allocate()
    ctx.tab_info[self:get_ssa_reference()] = {mem_ref = idx, shared_depth = 0}
    return ('%s\n%s\n%s'):format(
        ctx.te_stack:store(self:get_ssa_reference(), 'true'),
        ctx.mem_stack:store_index(idx, asize_idx, arith_utils.const_to_smt_bv(asize)),
        ctx.mem_stack:store_index(idx, hsize_idx, arith_utils.const_to_smt_bv(hsize))
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
