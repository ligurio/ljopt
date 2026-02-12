local bit = require('bit')
local ffi = require('ffi')

local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeTNEWTab = {}
ir_node.extended(impls.IRNodeTNEWTab, ir_node.ir_node_base)

function impls.IRNodeTNEWTab:to_smt_lib(ctx)
    local asize = tonumber(self:get_left_op():sub(2))
    local hsize = tonumber(self:get_right_op():sub(2))
    local hsize = bit.lshift(1, hsize) - 1   -- 2^x
    
    local asize_idx = constants.TAB_OFFSETS.asize
    local hmask_idx = constants.TAB_OFFSETS.hmask
    local hsize_idx = constants.TAB_OFFSETS.hsize

    local idx, init = ctx.mem_stack:allocate()
    ctx.tab_info[self:get_ssa_reference()] = {mem_ref = idx, meta = nil}
    return ('%s\n%s\n%s\n%s\n%s'):format(
        ctx.te_stack:store(self:get_ssa_reference(), 'true'),
        init,
        ctx.mem_stack:store_index(idx, asize_idx, arith_utils.const_to_smt_bv(asize)),
        ctx.mem_stack:store_index(idx, hmask_idx, arith_utils.const_to_smt_bv(hsize)),
        ctx.mem_stack:store_index(idx, hsize_idx, arith_utils.const_to_smt_bv(0))
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
