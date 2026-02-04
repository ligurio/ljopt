local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeULTNum = {}
ir_node.extended(impls.IRNodeULTNum, ir_node.ir_node_base)

function impls.IRNodeULTNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(not (fp.geq %s %s))',
        left_op, right_op
    )
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

impls.IRNodeULTInt = { op_str = 'bvult' }
ir_node.extended(impls.IRNodeULTInt, bin_op.BinOpGuardInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
