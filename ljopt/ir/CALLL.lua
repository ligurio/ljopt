local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')
local op_type = require('ljopt.ir.op_type')
local constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeCALLLP32 = {}
ir_node.extended(impls.IRNodeCALLLP32, ir_node.ir_node_base)

function impls.IRNodeCALLLP32:to_smt_lib(ctx)
    local cargs = self:get_left_op()
    local name = self:get_right_op()
    local ssa_ref = self:get_ssa_reference()

    if name:get_lit() == 'lj_buf_putstr_reverse' then
        local args = cargs:get_carg()
        local buf = args[1]
        local idx = ctx.tab_info[buf:get_ssa()].mem_ref
        ctx.tab_info[ssa_ref] = {mem_ref = idx, meta = nil}

        local slot_id = arith_utils.const_str_to_memcell(
            constants.FIELD_TAB_PREFIX .. 'bufhdr'
        )

        local prev = ctx.mem_stack:load_index(idx, slot_id, op_type.STR)
        local value = ir_node.retrieve_str_op(args[2], ctx)

        local res = ('(str.++ %s (str_reverse %s))'):format(prev, value)
        return ctx.mem_stack:store_index(idx, slot_id, res, op_type.STR)
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
