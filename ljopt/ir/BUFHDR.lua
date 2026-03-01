local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')
local op_type = require('ljopt.ir.op_type')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeBUFHDRP32 = {}
ir_node.extended(impls.IRNodeBUFHDRP32, ir_node.ir_node_base)

function impls.IRNodeBUFHDRP32:to_smt_lib(ctx)
    local mode = self:get_right_op()
    local idx, init
    local slot_id
    local ssa_ref = self:get_ssa_reference()
    if mode:get_lit() == 'RESET' then
        idx, init = ctx.mem_stack:allocate(ssa_ref)
        ctx.tab_info[ssa_ref] = {mem_ref = idx, meta = nil}

        slot_id = arith_utils.const_str_to_memcell(constants.STRING_BUFF_SLOT)
    else
        utils.unreachable('is_implemented should have returned false.')
    end

    return ('%s\n%s\n%s'):format(
        ctx.mem_stack:store_index(
            idx, slot_id, arith_utils.const_str_to_smt_str(''), op_type.STR
        ),
        ctx.op_stack:store(
            ssa_ref, 'i64', arith_utils.const_num_to_smt_bv(idx)
        ),
        init
    )
end

local function instance(node_str)
    return impls[node_str]
end

function impls.IRNodeBUFHDRP32.is_implemented(_flags, _type, _opcode,
                                             _left_op, right_op_val)
    local right_op = right_op_val:get_lit()
    if right_op == 'RESET' then
        return true
    end
    return false
end

return {
    instance = instance
}
