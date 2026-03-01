local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeBinOpBase = {}
ir_node.extended(IRNodeBinOpBase, ir_node.ir_node_base)

local IRNodeBinOpNum = {}
ir_node.extended(IRNodeBinOpNum, IRNodeBinOpBase)

local IRNodeBinOpInt = {}
ir_node.extended(IRNodeBinOpInt, IRNodeBinOpBase)

local IRNodeBinOpI64 = {}
ir_node.extended(IRNodeBinOpI64, IRNodeBinOpBase)

local IRNodeBinOpP64 = {}
ir_node.extended(IRNodeBinOpP64, IRNodeBinOpBase)

-- Implements any binary operation
-- with `num` as left and right argument
function IRNodeBinOpNum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, self:get_type()
    )
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
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_int_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function IRNodeBinOpI64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_i64_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_i64_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function IRNodeBinOpP64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_p64_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_i64_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    assert(self:get_left_op():is_ssa())
    ctx.tab_info[self:get_ssa_reference()] = ctx.tab_info[self:get_left_op().value]
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local IRNodeBinOpGuardNum = {}
ir_node.extended(IRNodeBinOpGuardNum, IRNodeBinOpBase)

local IRNodeBinOpGuardInt = {}
ir_node.extended(IRNodeBinOpGuardInt, IRNodeBinOpBase)

local IRNodeBinOpGuardI64 = {}
ir_node.extended(IRNodeBinOpGuardI64, IRNodeBinOpBase)

function IRNodeBinOpGuardNum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

function IRNodeBinOpGuardInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_int_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

function IRNodeBinOpGuardI64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_i64_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_i64_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

return {
    BinOpNum = IRNodeBinOpNum,
    BinOpInt = IRNodeBinOpInt,
    BinOpI64 = IRNodeBinOpI64,
    BinOpP64 = IRNodeBinOpP64,
    BinOpGuardNum = IRNodeBinOpGuardNum,
    BinOpGuardInt = IRNodeBinOpGuardInt,
    BinOpGuardI64 = IRNodeBinOpGuardI64,
}
