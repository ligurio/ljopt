local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local constants = require('ljopt.smt_constants')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeBUFSTRStr = {}
ir_node.extended(impls.IRNodeBUFSTRStr, ir_node.ir_node_base)

function impls.IRNodeBUFSTRStr:to_smt_lib(ctx)
    -- Simply load String value to op_stack from memory
    -- where the buffer has accumulated it.
    local mode = self:get_right_op()

    local slot_id = arith_utils.const_str_to_memcell(constants.STRING_BUFF_SLOT)

    local ssa_ref = self:get_ssa_reference()
    local idx = ctx.op_stack:load(mode:get_ssa(), op_type.TAB)
    local loaded = ctx.mem_stack:load_index(idx, slot_id, op_type.STR)

    -- Propagate the buffer's concatenated constant content so a
    -- downstream STRTO can const-fold to a concrete FP literal,
    -- matching what LuaJIT FOLD does on the opt side. The left op
    -- is the latest BUFPUT in the chain — it carries the
    -- accumulated string. The right op is the BUFHDR, which only
    -- holds the empty initial buffer.
    local data_ssa = self:get_left_op():get_ssa()
    local buf_const = ctx.const_strs[data_ssa]
    if buf_const ~= nil then
        ctx.const_strs[ssa_ref] = buf_const
    end

    return ctx.op_stack:store(ssa_ref, op_type.STR, loaded)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
