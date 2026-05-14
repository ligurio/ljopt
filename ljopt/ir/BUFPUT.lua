local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')
local op_type = require('ljopt.ir.op_type')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeBUFPUTP32 = {}
ir_node.extended(impls.IRNodeBUFPUTP32, ir_node.ir_node_base)

function impls.IRNodeBUFPUTP32:to_smt_lib(ctx)
    local ref = self:get_left_op()

    local right = ir_node.retrieve_str_op(self:get_right_op(), ctx)

    local ssa_ref = self:get_ssa_reference()
    local idx = ctx.op_stack:load(ref:get_ssa(), op_type.TAB)

    local slot_id = arith_utils.const_str_to_memcell(constants.STRING_BUFF_SLOT)

    local prev = ctx.mem_stack:load_index(idx, slot_id, op_type.STR)
    local res = ("(str.++ %s %s)"):format(prev, right)

    -- Propagate concatenated constant string from buffer + right
    -- operand. Matches LuaJIT FOLD: opt may emit BUFPUT with a
    -- pre-concatenated literal, so unopt's symbolic str.++ chain
    -- needs the same const-folded value as value at STRTO.
    local buf_const = ctx.const_strs[ref:get_ssa()]
    local right_const = utils.resolve_const_str(self:get_right_op(), ctx)
    if buf_const ~= nil and right_const ~= nil then
        ctx.const_strs[ssa_ref] = buf_const .. right_const
    end

    return ('%s\n%s'):format(
        ctx.mem_stack:store_index(idx, slot_id, res, op_type.STR),
        ctx.op_stack:store(ssa_ref, op_type.TAB, idx)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
