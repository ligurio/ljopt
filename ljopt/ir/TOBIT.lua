local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')

local IRNodeTOBIT = {}
ir_node.extended(IRNodeTOBIT, ir_node.ir_node_base)

function IRNodeTOBIT:to_smt_lib(ctx)
    -- TOBIT converts a floating-point `num` to a 32-bit integer
    -- using round-to-nearest-even (the "add 2^52+2^51" trick).
    -- Left operand is the num value; right operand is the TOBIT
    -- constant (ignored for SMT purposes).
    local left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
    -- Convert at 64 bits and wrap, not `fp.to_sbv 32`: bit.tobit
    -- is defined modulo 2^32 (the trick keeps the low 32 mantissa
    -- bits), while fp.to_sbv 32 is *unspecified* once the value
    -- leaves int32 range, which let the solver answer anything.
    -- That made lj_opt_narrow's `TOBIT((double)i + (double)j)` ->
    -- `ADD int i j` read as a miscompile for every i+j that
    -- overflows int32, even though both wrap identically. Same
    -- idiom as CONV `int.num`.
    local data = arith_utils.wrap_i32(
        ('((_ fp.to_sbv 64) RNE %s)'):format(left_op)
    )

    local ssa_ref = self:get_ssa_reference()
    local te = ""
    if self:get_flags().irt_guard then
        te = ctx.te_stack:store(ssa_ref, 'true') .. '\n'
    end
    return te .. ctx.op_stack:store(
        ssa_ref, self:get_type(), data
    )
end

local function instance(_node_str)
    return IRNodeTOBIT
end

return {
    instance = instance
}
