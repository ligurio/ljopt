local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')
local bit = require('bit')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeBUFSTRStr = {}
ir_node.extended(impls.IRNodeBUFSTRStr, ir_node.ir_node_base)

function impls.IRNodeBUFSTRStr:to_smt_lib(ctx)
    -- local typ = self:get_left_op()
    local mode = self:get_right_op()
    assert(mode:is_ssa(), mode.kind)

    local ssa_ref = self:get_ssa_reference()
    local idx = ctx.tab_info[mode.value].mem_ref
    ctx.tab_info[ssa_ref] = {mem_ref = idx, meta = nil}
    return ('%s'):format(
        ctx.op_stack:store(ssa_ref, 'i64', arith_utils.const_num_to_smt_bv(idx))
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
