local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')
local bit = require('bit')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeBUFHDRP32 = {}
ir_node.extended(impls.IRNodeBUFHDRP32, ir_node.ir_node_base)

function impls.IRNodeBUFHDRP32:to_smt_lib(ctx)
    -- local typ = self:get_left_op()
    local mode = self:get_right_op()
    assert(mode:is_lit(), mode.kind)
    assert(mode.value == 'RESET', mode.value)

    local ssa_ref = self:get_ssa_reference()
    local idx, init = ctx.string_stack:allocate()
    ctx.tab_info[ssa_ref] = {mem_ref = idx, meta = nil}

    return ('%s\n%s'):format(
        ctx.op_stack:store(ssa_ref, 'i64', arith_utils.const_num_to_smt_bv(idx)),
        init
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
