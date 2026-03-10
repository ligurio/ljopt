local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeFPMATHNum = {}
ir_node.extended(impls.IRNodeFPMATHNum, ir_node.ir_node_base)

local const_fns = {
    ['floor'] = math.floor,
    ['ceil'] = math.ceil,
    ['trunc'] = math.modf,
    ['sqrt'] = math.sqrt,
}

function impls.IRNodeFPMATHNum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = self:get_right_op():get_lit()
    local ssa_ref = self:get_ssa_reference()
    local type = self:get_type()

    local result
    if right_op == 'floor' then
        local data = ('(fp.roundToIntegral RTN %s)'):format(left_op)
        result = ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'ceil' then
        local data = ('(fp.roundToIntegral RTP %s)'):format(left_op)
        result = ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'trunc' then
        local data = ('(fp.roundToIntegral RTZ %s)'):format(left_op)
        result = ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'sqrt' then
        local data = ('(fp.sqrt RNE %s)'):format(left_op)
        result = ctx.op_stack:store(ssa_ref, type, data)
    else
        utils.unreachable('It should have been marked as NYI: ' .. right_op)
    end

    local fn = const_fns[right_op]
    if fn then
        local lc = utils.resolve_const(self:get_left_op(), ctx)
        if lc ~= nil then
            ctx.const_nums[ssa_ref] = fn(lc)
        end
    end

    return result
end

local function instance(node_str)
    return impls[node_str]
end

function impls.IRNodeFPMATHNum.is_implemented(_flags, _type, _opcode,
                                              _left_op, right_op_val)
    local right_op = right_op_val:get_lit()
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
