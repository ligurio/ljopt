local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeEQBase = {}
ir_node.extended(IRNodeEQBase, ir_node.ir_node_base)

local impls = {}

-- At least Z3 and Bitwuzla expect `=` for floating point
-- comparison.
impls.IRNodeEQNum = {}
ir_node.extended(impls.IRNodeEQNum, ir_node.ir_node_base)

function impls.IRNodeEQNum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data
    -- `x == x` is LuaJIT's NaN guard: in IEEE it is false only
    -- for NaN. SMT-LIB `=` is structural, so `(= x x)` is always
    -- true. Model the self-comparison as an explicit non-NaN
    -- check instead.
    if left_op == right_op then
        data = ('(not (fp.isNaN %s))'):format(left_op)
    else
        data = string.format('(= %s %s)', left_op, right_op)
    end
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end


impls.IRNodeEQInt = { op_str = '=' }
ir_node.extended(impls.IRNodeEQInt, bin_op.BinOpGuardInt)

impls.IRNodeEQI64 = { op_str = '=' }
ir_node.extended(impls.IRNodeEQI64, bin_op.BinOpGuardI64)

impls.IRNodeEQU32 = { op_str = '=' }
ir_node.extended(impls.IRNodeEQU32, bin_op.BinOpGuardU32)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
