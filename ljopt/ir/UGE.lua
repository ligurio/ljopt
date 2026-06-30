local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeUGENum = {}
ir_node.extended(impls.IRNodeUGENum, ir_node.ir_node_base)

function impls.IRNodeUGENum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(not (fp.lt %s %s))',
        left_op, right_op
    )
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

impls.IRNodeUGEInt = { op_str = 'bvuge' }
ir_node.extended(impls.IRNodeUGEInt, bin_op.BinOpGuardInt)

impls.IRNodeUGEU32 = { op_str = 'bvuge' }
ir_node.extended(impls.IRNodeUGEU32, bin_op.BinOpGuardU32)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
