local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')

local IRNodeTOBIT = {}
ir_node.extended(IRNodeTOBIT, ir_node.ir_node_base)

function IRNodeTOBIT:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
    local data, tie = arith_utils.fp_tobit(left_op)

    local ssa_ref = self:get_ssa_reference()
    local te = ""
    if self:get_flags().irt_guard then
        te = ctx.te_stack:store(ssa_ref, 'true') .. '\n'
    end
    return tie .. '\n' .. te .. ctx.op_stack:store(
        ssa_ref, self:get_type(), data
    )
end

local function instance(_node_str)
    return IRNodeTOBIT
end

return {
    instance = instance
}
