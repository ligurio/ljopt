local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')
local op_type = require('ljopt.ir.op_type')
local constants = require('ljopt.smt_constants')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeCALLLP32 = {}
ir_node.extended(impls.IRNodeCALLLP32, ir_node.ir_node_base)

function impls.IRNodeCALLLP32:to_smt_lib(ctx)
    local cargs = self:get_left_op()
    local name = self:get_right_op()

    if name:get_lit() == 'lj_buf_putstr_reverse' then
        local args = cargs:get_carg()
        local buf = args[1]
        local idx = ctx.op_stack:load(buf:get_ssa(), op_type.TAB)

        local slot_id = arith_utils.const_str_to_memcell(
            constants.FIELD_TAB_PREFIX .. 'bufhdr'
        )

        local prev = ctx.mem_stack:load_index(idx, slot_id, op_type.STR)

        local known = utils.resolve_const_str(args[2], ctx)
        local reversed
        if known ~= nil then
            reversed = arith_utils.const_str_to_smt_str(known:reverse())
        else
            reversed = ('(str_reverse %s)'):format(
                ir_node.retrieve_str_op(args[2], ctx)
            )
        end

        local res = ('(str.++ %s %s)'):format(prev, reversed)
        -- A buffer put returns the buffer, and the next BUFPUT
        -- (or the closing BUFSTR) chains from *this* ref, not
        -- from the BUFHDR. Without republishing the pointer the
        -- follow-up op loaded an unconstrained op-stack slot and
        -- wrote its string somewhere else entirely, so any
        -- `s:reverse() .. t` shape read as a miscompile.
        local ssa_ref = self:get_ssa_reference()
        local buf_const = ctx.const_strs[buf:get_ssa()]
        if buf_const ~= nil and known ~= nil then
            ctx.const_strs[ssa_ref] = buf_const .. known:reverse()
        end
        return ('%s\n%s'):format(
            ctx.mem_stack:store_index(idx, slot_id, res, op_type.STR),
            ctx.op_stack:store(ssa_ref, op_type.TAB, idx)
        )
    end

    error('CALLL: unsupported function ' .. tostring(name:get_lit()))
end

function impls.IRNodeCALLLP32.is_implemented(_flags, _type, _opcode,
                                             _left_op, right_op)
    if right_op == nil or not right_op:is_lit() then
        return false
    end
    if right_op:get_lit() == 'lj_buf_putstr_reverse' then
        return true
    end
    return false
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
