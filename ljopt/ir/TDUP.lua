local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')
local utils = require('ljopt.utils')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeTDUPTab = {}
ir_node.extended(impls.IRNodeTDUPTab, ir_node.ir_node_base)

function impls.IRNodeTDUPTab:to_smt_lib(ctx)
    -- address, asize, hsize
    local _, asize, _ = self:get_left_op():match("{(.-):(.-):(.-)}")

    local asize_id = tonumber(
        utils.hash(constants.FIELD_TAB_PREFIX .. 'tab.asize')
    )
    local hmask_id = tonumber(
        utils.hash(constants.FIELD_TAB_PREFIX .. 'tab.hmask')
    )

    local ssa_ref = self:get_ssa_reference()
    local idx, formula = ctx.mem_stack:allocate(ssa_ref)

    local smt_asize = arith_utils.const_num_to_smt_bv(tonumber(asize))
    local smt_hsize = arith_utils.const_num_to_smt_bv(0)
    return ('%s\n%s\n%s\n%s\n%s'):format(
        formula,
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.mem_stack:store_index(idx, asize_id, smt_asize),
        ctx.mem_stack:store_index(idx, hmask_id, smt_hsize),
        ctx.op_stack:store(ssa_ref, 'i64', arith_utils.const_num_to_smt_bv(idx))
    )
end

local function instance(_node_str)
    return nil -- impls[node_str]
end

function impls.IRNodeTDUPTab.is_implemented(_flags, _type, _opcode,
                                            _left_op, _right_op)
    -- TDUP from const table is hard.
    return false
end


return {
    instance = instance
}
