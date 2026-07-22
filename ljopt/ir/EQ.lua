local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local IRNodeEQBase = {}
ir_node.extended(IRNodeEQBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeEQNum = {}
ir_node.extended(impls.IRNodeEQNum, ir_node.ir_node_base)

function impls.IRNodeEQNum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(fp.eq %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end


impls.IRNodeEQFun = {}
ir_node.extended(impls.IRNodeEQFun, ir_node.ir_node_base)

function impls.IRNodeEQFun:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local data = 'true'
    if left_op:is_fun() and right_op:is_fun() then
        data = tostring(
            op_type.to_string(left_op) == op_type.to_string(right_op)
        )
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
