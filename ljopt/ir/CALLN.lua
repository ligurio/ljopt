local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')
local utils = require('ljopt.utils')

local supported_math_fns = {
    ['acos'] = math.acos,
    ['asin'] = math.asin,
    ['atan'] = math.atan,
    ['cos'] = math.cos,
    ['cosh'] = math.cosh,
    ['exp'] = math.exp,
    ['log'] = math.log,
    ['log10'] = math.log10,
    ['sin'] = math.sin,
    ['sinh'] = math.sinh,
    ['tan'] = math.tan,
    ['tanh'] = math.tanh,
}

local impls = {}

impls.IRNodeCALLNNum = {}
ir_node.extended(impls.IRNodeCALLNNum, ir_node.ir_node_base)

function impls.IRNodeCALLNNum:to_smt_lib(ctx)
    local fn_name_op = self:get_right_op()
    local fn_name = fn_name_op:get_lit()
    local smt_fn = 'math_' .. fn_name

    local arg_op = self:get_left_op()
    if arg_op:is_carg() then
        arg_op = arg_op:get_carg()[1]
    end
    local ssa_ref = self:get_ssa_reference()

    local arg_fp = ir_node.retrieve_num_op(arg_op, ctx, 'num')
    local result_fp = ('(%s %s)'):format(smt_fn, arg_fp)

    local axiom = ''
    -- When argument is constant, define the actual result.
    local const_val = utils.resolve_const(arg_op, ctx)
    local lua_fn = supported_math_fns[fn_name]
    if const_val ~= nil and lua_fn then
        local result_val = lua_fn(const_val)
        local input_fp = arith_utils.const_num_to_smt_fp(const_val)
        local result_fp_const = arith_utils.const_num_to_smt_fp(result_val)
        axiom = ('\n(assert (= (%s %s) %s))'):format(
            smt_fn, input_fp, result_fp_const
        )
        ctx.const_nums[ssa_ref] = result_val
    end

    return ctx.op_stack:store(ssa_ref, 'num', result_fp) .. axiom
end

function impls.IRNodeCALLNNum.is_implemented(_flags, _type, _opcode,
                                             left_op, right_op)
    if left_op == nil or right_op == nil then
        return false
    end
    if not right_op:is_lit() then
        return false
    end
    local fn_name = right_op:get_lit()
    return supported_math_fns[fn_name] ~= nil
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
