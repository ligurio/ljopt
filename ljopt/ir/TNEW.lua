local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')
local bit = require('bit')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeTNEWTab = {}
ir_node.extended(impls.IRNodeTNEWTab, ir_node.ir_node_base)

function impls.IRNodeTNEWTab:to_smt_lib(ctx)
    local asize = tonumber(self:get_left_op():sub(2))
    local hsize = tonumber(self:get_right_op():sub(2))
    hsize = bit.lshift(1, hsize) - 1   -- 2^x - 1

    local asize_id = tostring(
        utils.hash(constants.FIELD_TAB_PREFIX .. 'tab.asize')
    )
    local hmask_id = tostring(
        utils.hash(constants.FIELD_TAB_PREFIX .. 'tab.hmask')
    )

    local ssa_ref = self:get_ssa_reference()
    local idx, init = ctx.mem_stack:allocate(ssa_ref)
    ctx.tab_info[ssa_ref] = {mem_ref = idx, meta = nil}

    local smt_asize = arith_utils.const_num_to_smt_bv(asize)
    local smt_hmask = arith_utils.const_num_to_smt_bv(hsize)
    return ('%s\n%s\n%s\n%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        init,
        ctx.mem_stack:store_index(idx, asize_id, smt_asize),
        ctx.mem_stack:store_index(idx, hmask_id, smt_hmask),
        ctx.op_stack:store(ssa_ref, 'i64', arith_utils.const_num_to_smt_bv(idx))
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
