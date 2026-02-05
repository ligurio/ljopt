local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeFPMATHNum = {}
ir_node.extended(impls.IRNodeFPMATHNum, ir_node.ir_node_base)


function impls.IRNodeFPMATHNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:get_right_op()
    local ssa_ref = self:get_ssa_reference()
    local type = self:get_type()
    if right_op == 'floor' then
        local data = ('(fp.roundToIntegral RTN %s)'):format(left_op)
        return ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'ceil' then
        local data = ('(fp.roundToIntegral RTP %s)'):format(left_op)
        return ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'trunc' then
        local data = ('(fp.roundToIntegral RTZ %s)'):format(left_op)
        return ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'sqrt' then
        local data = ('(fp.sqrt RNE %s)'):format(left_op)
        return ctx.op_stack:store(ssa_ref, type, data)
    else
        utils.unreachable('It should have been marked as NYI: ' .. right_op)
    end
end

local function instance(node_str)
    return impls[node_str]
end

function impls.IRNodeFPMATHNum.is_implemented(_flags, _type, _opcode,
                                              _left_op, right_op)
    local nyi_table = {
        'cos',
        'exp',
        'exp2',
        'log',
        'log10',
        'log2',
        'sin',
    }
    -- SMT can't handle most of the nonlinear functions.
    -- It can be implemented in future using uninterpreted
    -- functions theory and axioms/properties of each function.
    -- In this way all possible optimizations will be handled.
    for _, value in ipairs(nyi_table) do
        if value == right_op then
            return false
        end
    end
    return true
end

return {
    instance = instance
}
