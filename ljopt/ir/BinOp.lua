local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')

local IRNodeBinOpBase = {}
ir_node.extended(IRNodeBinOpBase, ir_node.ir_node_base)

local IRNodeBinOpNum = {}
ir_node.extended(IRNodeBinOpNum, IRNodeBinOpBase)

local IRNodeBinOpInt = {}
ir_node.extended(IRNodeBinOpInt, IRNodeBinOpBase)

local IRNodeBinOpI64 = {}
ir_node.extended(IRNodeBinOpI64, IRNodeBinOpBase)

local IRNodeBinOpU32 = {}
ir_node.extended(IRNodeBinOpU32, IRNodeBinOpBase)

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

    if self.const_fn then
        local lc = utils.resolve_const(self:get_left_op(), ctx)
        local rc = utils.resolve_const(self:get_right_op(), ctx)
        if lc ~= nil and rc ~= nil then
            ctx.const_nums[self:get_ssa_reference()] = self.const_fn(lc, rc)
        end
    end

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

-- Unsigned 32-bit arithmetic: run the op at 64-bit width, then
-- wrap_u32 the result back to canonical form (see arith_utils).
function IRNodeBinOpU32:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_u32_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_u32_op(self:get_right_op(), ctx, type)
    local data = arith_utils.wrap_u32(
        string.format('(%s %s %s)', self.op_str, left_op, right_op)
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end


local IRNodeBinOpGuardNum = {}
ir_node.extended(IRNodeBinOpGuardNum, IRNodeBinOpBase)

local IRNodeBinOpGuardInt = {}
ir_node.extended(IRNodeBinOpGuardInt, IRNodeBinOpBase)

local IRNodeBinOpGuardI64 = {}
ir_node.extended(IRNodeBinOpGuardI64, IRNodeBinOpBase)

local IRNodeBinOpGuardU32 = {}
ir_node.extended(IRNodeBinOpGuardU32, IRNodeBinOpBase)

function IRNodeBinOpGuardNum:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_num_op(self:get_right_op(), ctx, type)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

function IRNodeBinOpGuardInt:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, type)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

function IRNodeBinOpGuardI64:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_i64_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_i64_op(self:get_right_op(), ctx, type)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

-- Unsigned 32-bit equality guard (= / distinct on canonical u32
-- BVs). LuaJIT lowers ordered u32 compares to ULT/ULE, not here.
function IRNodeBinOpGuardU32:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_u32_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_u32_op(self:get_right_op(), ctx, type)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

return {
    BinOpNum = IRNodeBinOpNum,
    BinOpInt = IRNodeBinOpInt,
    BinOpI64 = IRNodeBinOpI64,
    BinOpU32 = IRNodeBinOpU32,
    BinOpGuardNum = IRNodeBinOpGuardNum,
    BinOpGuardInt = IRNodeBinOpGuardInt,
    BinOpGuardI64 = IRNodeBinOpGuardI64,
    BinOpGuardU32 = IRNodeBinOpGuardU32,
}
