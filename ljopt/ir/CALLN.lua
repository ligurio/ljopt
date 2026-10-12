local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')
local utils = require('ljopt.utils')

local supported_math_fns = {
    ['acos'] = math.acos,
    ['asin'] = math.asin,
    ['atan'] = math.atan,
    ['atan2'] = math.atan2,
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

-- math fns taking 2 args; left_op is a CARG holding both.
local two_arg_fns = {
    ['atan2'] = true,
}

-- Arguments a call can be folded on without its operand being a
-- constant here. LuaJIT folds a call on a literal through
-- kfold_fpcall1, and a loop makes literals of values this trace
-- only loads: a carried value folded to a constant, or a load
-- forwarded from a constant store, reaches the copied call as a
-- KNUM. The optimized side then holds the folded number, while
-- here the uninterpreted function can answer anything for the
-- same argument. The special points and the IR fuzzer's KNUM pool
-- (irfuzz/gen_table.lua) are where that happens.
local KNOWN_ARGS = {
    0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0, 3.5, -3.5,
    1 / 0, -1 / 0, 0 / 0,
}

-- Pin `smt_fn` to the real function at KNOWN_ARGS, once per
-- trace. The host's math.* is the libm LuaJIT folds with, so the
-- axioms state what the optimizer computes, not an approximation.
local function known_points(ctx, fn_name, smt_fn, lua_fn)
    if ctx.math_points[fn_name] then
        return ''
    end
    ctx.math_points[fn_name] = true
    local out = {}
    for _, x in ipairs(KNOWN_ARGS) do
        table.insert(out, ('(assert (= (%s %s) %s))'):format(
            smt_fn, arith_utils.const_num_to_smt_fp(x),
            arith_utils.const_num_to_smt_fp(lua_fn(x))
        ))
    end
    return '\n' .. table.concat(out, '\n')
end

local impls = {}

impls.IRNodeCALLNNum = {}
ir_node.extended(impls.IRNodeCALLNNum, ir_node.ir_node_base)

function impls.IRNodeCALLNNum:to_smt_lib(ctx)
    local fn_name = self:get_right_op():get_lit()
    local smt_fn = 'math_' .. fn_name
    local ssa_ref = self:get_ssa_reference()

    local raw_left = self:get_left_op()
    local arg_ops
    if two_arg_fns[fn_name] then
        assert(raw_left:is_carg(),
            'two-arg CALLN expects CARG left_op, got: ' .. raw_left.type
        )
        local carg = raw_left:get_carg()
        arg_ops = { carg[1], carg[2] }
    else
        local single = raw_left:is_carg() and raw_left:get_carg()[1] or raw_left
        arg_ops = { single }
    end

    local arg_fps = {}
    local arg_consts = {}
    local all_const = true
    for i, op in ipairs(arg_ops) do
        arg_fps[i] = ir_node.retrieve_num_op(op, ctx, 'num')
        arg_consts[i] = utils.resolve_const(op, ctx)
        if arg_consts[i] == nil then all_const = false end
    end
    local result_fp = ('(%s %s)'):format(smt_fn, table.concat(arg_fps, ' '))

    local axiom = ''
    local lua_fn = supported_math_fns[fn_name]
    if all_const and lua_fn then
        local result_val = lua_fn((unpack or table.unpack)(arg_consts))
        local const_args = {}
        for i, v in ipairs(arg_consts) do
            const_args[i] = arith_utils.const_num_to_smt_fp(v)
        end
        axiom = ('\n(assert (= (%s %s) %s))'):format(
            smt_fn, table.concat(const_args, ' '),
            arith_utils.const_num_to_smt_fp(result_val)
        )
        ctx.const_nums[ssa_ref] = result_val
    end
    if lua_fn and not two_arg_fns[fn_name] then
        axiom = axiom .. known_points(ctx, fn_name, smt_fn, lua_fn)
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
