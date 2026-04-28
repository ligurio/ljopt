local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeCNEWCdt = {}
ir_node.extended(impls.IRNodeCNEWCdt, ir_node.ir_node_base)

function impls.IRNodeCNEWCdt:to_smt_lib(ctx)
    local maybe_size = self:get_right_op()

    local cdt_size = arith_utils.const_str_to_memcell(
        constants.FIELD_TAB_PREFIX .. 'cdata.size'
    )

    local cdt_type = arith_utils.const_str_to_memcell(
        constants.FIELD_TAB_PREFIX .. 'cdata.ctypeid'
    )

    local ssa_ref = self:get_ssa_reference()
    local idx, init = ctx.mem_stack:allocate()

    local smt_cdt_size
    if maybe_size == nil then
        smt_cdt_size = arith_utils.const_num_to_smt_bv(0)
    elseif maybe_size:is_num() then
        smt_cdt_size = arith_utils.const_num_to_smt_bv(maybe_size:get_num())
    else
        smt_cdt_size = ir_node.retrieve_i64_op(maybe_size, ctx, 'i64')
    end
    -- LJ assigns a fresh ctype id per anonymous ffi.typeof(...).
    -- The id is an opaque LJ-internal counter, not a semantic
    -- value, and nothing reads it back from mem_stack — store a
    -- stable canonical 0 so equivalent traces match.
    local smt_cdt_type = arith_utils.const_num_to_smt_bv(0)
    return ('%s\n%s\n%s\n%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        init,
        ctx.mem_stack:store_index(idx, cdt_type, smt_cdt_type, 'i64'),
        ctx.mem_stack:store_index(idx, cdt_size, smt_cdt_size, 'i64'),
        ctx.op_stack:store(ssa_ref, 'cdt', arith_utils.const_int_to_smt_bv(idx))
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
