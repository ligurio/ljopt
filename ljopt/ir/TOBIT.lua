local bit = require('bit')
local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local IRNodeTOBIT = {}
ir_node.extended(IRNodeTOBIT, ir_node.ir_node_base)

function IRNodeTOBIT:to_smt_lib(ctx)
    local ssa_ref = self:get_ssa_reference()

    -- bit.tobit wraps to a 32-bit two's complement value, which
    -- only coincides with a bounded int conversion while
    -- |x| < 2^31. The fp.to_sbv used below is undefined outside
    -- that range (e.g. tobit(0xffffffff) == -1, but 4294967295.0
    -- does not fit a signed 32-bit fp.to_sbv). Fold a constant
    -- operand with the real bit.tobit and emit the sign-extended
    -- literal instead.
    local const_val = utils.resolve_const(self:get_left_op(), ctx)
    if const_val ~= nil then
        local b = bit.tobit(const_val)
        return ctx.op_stack:store(
            ssa_ref, self:get_type(),
            arith_utils.const_i64_to_smt_bv(b)
        )
    end

    -- TOBIT converts a floating-point `num` to a 32-bit integer
    -- using round-to-nearest-even (the "add 2^52+2^51" trick).
    -- Left operand is the num value; right operand is the TOBIT
    -- constant (ignored for SMT purposes).
    local left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
    local data = arith_utils.smt_fp_to_int(left_op, 'RNE')

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
