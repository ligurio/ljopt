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
    local ssa_ref = self:get_ssa_reference()
    if mode:get_lit() == 'RESET' then
        local idx, init = ctx.mem_stack:allocate()
        local slot_id =
            arith_utils.const_str_to_memcell(constants.STRING_BUFF_SLOT)
        -- Track the empty initial buffer content for
        -- const-folding through BUFPUT/BUFSTR/STRTO.
        ctx.const_strs[ssa_ref] = ''
        return ('%s\n%s\n%s'):format(
            ctx.mem_stack:store_index(
                idx, slot_id, arith_utils.const_str_to_smt_str(''), op_type.STR
            ),
            ctx.op_stack:store(ssa_ref, op_type.TAB, tostring(idx)),
            init
        )
    elseif mode:get_lit() == 'APPEND' then
        -- APPEND continues writing into the buffer of the left
        -- operand. Re-use its TAB idx and leave existing contents
        -- untouched — subsequent BUFPUTs concatenate onto it.
        local src_ssa = self:get_left_op():get_ssa()
        local idx = ctx.op_stack:load(src_ssa, op_type.TAB)
        -- Inherit buffer constant content from the source.
        local src_const = ctx.const_strs[src_ssa]
        if src_const ~= nil then
            ctx.const_strs[ssa_ref] = src_const
        end
        return ctx.op_stack:store(ssa_ref, op_type.TAB, idx)
    else
        utils.unreachable('is_implemented should have returned false.')
    end
end

local function instance(node_str)
    return impls[node_str]
end

function impls.IRNodeBUFHDRP32.is_implemented(_flags, _type, _opcode,
                                             _left_op, right_op_val)
    local right_op = right_op_val:get_lit()
    if right_op == 'RESET' or right_op == 'APPEND' then
        return true
    end
    return false
end

return {
    instance = instance
}
