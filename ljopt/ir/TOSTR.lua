local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeTOSTRStr = {}
ir_node.extended(impls.IRNodeTOSTRStr, ir_node.ir_node_base)

function impls.IRNodeTOSTRStr:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local ssa_ref = self:get_ssa_reference()

    -- TOSTR carries its mode (NUM/INT/CHAR) in the right operand.
    -- The decimal modes (NUM/INT) convert a value to its decimal
    -- string; CHAR converts a byte code into the single-character
    -- string, which tostr_num would get wrong (char 65 is "A",
    -- not "65"). Materialize CHAR on a constant code exactly.
    local mode = (right_op ~= nil) and op_type.to_string(right_op) or ''
    if mode == 'CHAR' then
        local code = utils.resolve_const(left_op, ctx)
        if code ~= nil then
            local s = string.char(code)
            ctx.const_strs[ssa_ref] = s
            local lit = s:gsub('\\', '\\\\'):gsub('"', '\\"')
            return ('%s\n%s'):format(
                ctx.te_stack:store(ssa_ref, 'true'),
                ctx.op_stack:store(
                    ssa_ref, op_type.STR, ('"%s"'):format(lit)
                )
            )
        end
    end

    -- Get the input as the native fp the tostring is applied to.
    -- An INT operand lives in an int-val cell, so reading it with
    -- get-fp (the NUM path) yields an unconstrained value
    -- unrelated to the integer; convert it to fp exactly like a
    -- num.int CONV.
    local fp
    local const_val
    if mode == 'INT' and left_op:is_ssa() then
        local int_bv = ir_node.retrieve_int_op(left_op, ctx, 'int')
        fp = arith_utils.smt_int_to_fp(int_bv)
    else
        fp = ir_node.retrieve_num_op(left_op, ctx, 'num')
        const_val = utils.resolve_const(left_op, ctx, op_type.NUM)
    end

    -- Apply uninterpreted function to convert FP to string.
    local str_expr = ('(tostr_num %s)'):format(fp)

    -- Roundtrip axiom: strto_num(tostr_num(x)) = x.
    -- It's simpler to use `forall`, but it's hard for Z3.
    local roundtrip = ('(assert (= (strto_num (tostr_num %s)) %s))'):format(
        fp, fp
    )

    -- When the argument is a known constant, emit the exact
    -- string value so the solver doesn't have to guess.
    local const_axiom = ''
    if const_val ~= nil then
        local str_val = tostring(const_val)
        const_axiom = ('\n(assert (= (tostr_num %s) "%s"))'):format(
            fp, str_val
        )
        ctx.const_strs[ssa_ref] = str_val
    end

    return ('%s\n%s\n%s%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.STR, str_expr),
        roundtrip,
        const_axiom
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
