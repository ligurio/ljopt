local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')
local op_type = require('ljopt.ir.op_type')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeCNEWICdt = {}
ir_node.extended(impls.IRNodeCNEWICdt, ir_node.ir_node_base)

function impls.IRNodeCNEWICdt:to_smt_lib(ctx)
    local typ = self:get_left_op()
    local value = self:get_right_op()

    local cdt_type = arith_utils.const_str_to_memcell(
        constants.FIELD_TAB_PREFIX .. 'cdata.ctypeid'
    )

    local cdt_value = arith_utils.const_str_to_memcell(
        constants.FIELD_TAB_PREFIX .. 'cdata.value'
    )

    local ssa_ref = self:get_ssa_reference()
    local idx, init = ctx.mem_stack:allocate()
    ctx.tab_info[ssa_ref] = {mem_ref = idx, meta = nil}

    local smt_value
    if value:is_num() then
        smt_value = arith_utils.const_num_to_smt_bv(value:get_num())
    elseif value:is_i64() then
        smt_value = arith_utils.const_i64_to_smt_bv(value:get_i64())
    elseif value:is_ssa() then
        smt_value = ir_node.retrieve_i64_op(
            value, ctx, 'i64'
        )
    else
        utils.unreachable(value.type)
    end

    local smt_cdt_type = arith_utils.const_num_to_smt_bv(typ:get_num())
    return ('%s\n%s\n%s\n%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        init,
        ctx.mem_stack:store_index(idx, cdt_type, smt_cdt_type, op_type.I64),
        ctx.mem_stack:store_index(idx, cdt_value, smt_value, op_type.I64),
        ctx.op_stack:store(ssa_ref, 'i64', arith_utils.const_num_to_smt_bv(idx))
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
