local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeCNEWCdt = {}
ir_node.extended(impls.IRNodeCNEWCdt, ir_node.ir_node_base)

function impls.IRNodeCNEWCdt:to_smt_lib(ctx)
    local value = self:get_left_op()
    local maybe_size = self:get_right_op()

    local cdt_size = arith_utils.const_str_to_memcell(
        constants.FIELD_TAB_PREFIX .. 'cdata.size'
    )

    local cdt_type = arith_utils.const_str_to_memcell(
        constants.FIELD_TAB_PREFIX .. 'cdata.ctypeid'
    )

    local ssa_ref = self:get_ssa_reference()
    local idx, init = ctx.mem_stack:allocate(ssa_ref)
    ctx.tab_info[ssa_ref] = {mem_ref = idx, meta = nil}

    local smt_cdt_size = arith_utils.const_num_to_smt_bv(
        maybe_size and maybe_size:get_num() or 0
    )
    local smt_cdt_type = arith_utils.const_num_to_smt_bv(value:get_num())
    return ('%s\n%s\n%s\n%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        init,
        ctx.mem_stack:store_index(idx, cdt_type, smt_cdt_type),
        ctx.mem_stack:store_index(idx, cdt_size, smt_cdt_size),
        ctx.op_stack:store(ssa_ref, 'i64', arith_utils.const_num_to_smt_bv(idx))
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
