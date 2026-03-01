local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeTOSTRStr = {}
ir_node.extended(impls.IRNodeTOSTRStr, ir_node.ir_node_base)

function impls.IRNodeTOSTRStr:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local ssa_ref = self:get_ssa_reference()

    -- Get the input value as a bitvector.
    local bv = ir_node.retrieve_i64_op(left_op, ctx, 'i64')

    -- Apply uninterpreted function to convert bv to string.
    local str_expr = ('(tostr_num %s)'):format(bv)

    -- Roundtrip axiom: strto_num(tostr_num(x)) = x.
    -- It's simpler to use `forall`, but it's hard for Z3.
    local roundtrip = ('(assert (= (strto_num (tostr_num %s)) %s))'):format(
        bv, bv
    )

    return ('%s\n%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.STR, str_expr),
        roundtrip
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
