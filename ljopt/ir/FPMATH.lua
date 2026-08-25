local arith_utils = require('ljopt.ir.arith_utils')
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
    ['log'] = math.log,
}

local uninterpreted_fns = {log = true}

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
    elseif uninterpreted_fns[right_op] ~= nil then
        local data = ('(math_%s %s)'):format(right_op, left_op)
        result = ctx.op_stack:store(ssa_ref, type, data)
    else
        utils.unreachable('It should have been marked as NYI: ' .. right_op)
    end

    local fn = const_fns[right_op]
    if fn then
        local lc = utils.resolve_const(self:get_left_op(), ctx)
        if lc ~= nil then
            local const_result = fn(lc)
            ctx.const_nums[ssa_ref] = const_result
            if uninterpreted_fns[right_op] ~= nil then
                result = result
                    .. ('\n(assert (= (math_%s %s) %s))'):format(
                        right_op,
                        arith_utils.const_num_to_smt_fp(lc),
                        arith_utils.const_num_to_smt_fp(const_result)
                    )
            end
        end
    end

    return result
end

local function instance(node_str)
    return impls[node_str]
end

-- An allowlist of what to_smt_lib actually emits, not a list of
-- what it does not: anything outside both sets used to pass the
-- gate and then hit `unreachable`, which killed the run. `tan`
-- was such a case.
local native_fns = {floor = true, ceil = true, trunc = true, sqrt = true}

function impls.IRNodeFPMATHNum.is_implemented(_flags, _type, _opcode,
                                              _left_op, right_op_val)
    if right_op_val == nil or not right_op_val:is_lit() then
        return false
    end
    local right_op = right_op_val:get_lit()
    return native_fns[right_op] == true
        or uninterpreted_fns[right_op] ~= nil
end

return {
    instance = instance
}
