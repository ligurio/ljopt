local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeSTRTONum = {}
ir_node.extended(impls.IRNodeSTRTONum, ir_node.ir_node_base)

function impls.IRNodeSTRTONum:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local ssa_ref = self:get_ssa_reference()

    local bv
    if left_op:is_str() then
        if tonumber(left_op:get_str()) then
            bv = arith_utils.const_num_to_smt_bv(tonumber(left_op:get_str()))
        else
            utils.unreachable("Apparently LuaJIT bug. LuaJIT emitted STRTO " ..
                              "for string, that is not convertible to number.")
        end
    else
        -- Apply uninterpreted function to convert string to bv.
        bv = ('(strto_num %s)'):format(
            ctx.op_stack:load(left_op:get_ssa(), op_type.STR)
        )
    end

    -- Store as i64 since strto_num returns a bitvector directly.
    return ctx.te_stack:store(ssa_ref, 'true') .. '\n' ..
        ctx.op_stack:store(ssa_ref, 'i64', bv)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
