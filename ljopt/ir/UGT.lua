local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeUGTNum = {}
ir_node.extended(impls.IRNodeUGTNum, ir_node.ir_node_base)

function impls.IRNodeUGTNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(not (fp.leq %s %s))',
        left_op, right_op
    )
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

impls.IRNodeUGTInt = { op_str = 'bvugt' }
ir_node.extended(impls.IRNodeUGTInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
