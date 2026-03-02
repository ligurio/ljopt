local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeTOBIT = {}
ir_node.extended(IRNodeTOBIT, ir_node.ir_node_base)

function IRNodeTOBIT:to_smt_lib(ctx)
    -- TOBIT converts a floating-point `num` to a 32-bit integer
    -- using round-to-nearest-even (the "add 2^52+2^51" trick).
    -- Left operand is the num value; right operand is the TOBIT
    -- constant (ignored for SMT purposes).
    local left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
    -- fp.to_sbv 32 with RNE, then sign-extend to 64-bit.
    local data = string.format(
        '((_ sign_extend 32) ((_ fp.to_sbv 32) RNE %s))', left_op
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
