local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeBinOpBase = {}
ir_node.extended(IRNodeBinOpBase, ir_node.ir_node_base)

local IRNodeBinOpNum = {}
ir_node.extended(IRNodeBinOpNum, IRNodeBinOpBase)

local IRNodeBinOpInt = {}
ir_node.extended(IRNodeBinOpInt, IRNodeBinOpBase)

local IRNodeBinOpI64 = {}
ir_node.extended(IRNodeBinOpI64, IRNodeBinOpBase)

function IRNodeBinOpNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local maybe_round = 'RNE'
    if self.ignore_rounding then
        maybe_round = ''
    end
    local data = string.format('(%s %s %s %s)',
        self.op_str, maybe_round, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function IRNodeBinOpInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function IRNodeBinOpI64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end


local IRNodeBinOpGuardNum = {}
ir_node.extended(IRNodeBinOpGuardNum, IRNodeBinOpBase)

local IRNodeBinOpGuardInt = {}
ir_node.extended(IRNodeBinOpGuardInt, IRNodeBinOpBase)

local IRNodeBinOpGuardI64 = {}
ir_node.extended(IRNodeBinOpGuardI64, IRNodeBinOpBase)

function IRNodeBinOpGuardNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

function IRNodeBinOpGuardInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

function IRNodeBinOpGuardI64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

return {
    BinOpNum = IRNodeBinOpNum,
    BinOpInt = IRNodeBinOpInt,
    BinOpI64 = IRNodeBinOpI64,
    BinOpGuardNum = IRNodeBinOpGuardNum,
    BinOpGuardInt = IRNodeBinOpGuardInt,
    BinOpGuardI64 = IRNodeBinOpGuardI64,
}
