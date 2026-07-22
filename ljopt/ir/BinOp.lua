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

-- int results are canonicalized with wrap_i32: `int` is int32 and
-- wraps mod 2^32 (see arith_utils). The type check matters --
-- some 64-bit nodes (e.g. BSAR i64) inherit this class and must
-- not be truncated.
--
-- PHI-marked (loop-carried) ops are exempt. A narrowed FORL
-- index wraps in reality too, but only because LuaJIT proved at
-- record time that it never can (entry invariant i <= stop,
-- stop+step checked non-overflowing) -- an invariant ljopt does
-- not model. Wrapping the loop-carried ADD faithfully lets z3
-- enter the loop at INT32_MAX, where the wrapped int side keeps
-- looping while the -O0 FP side exits: a real divergence on an
-- unreachable entry, i.e. a false SAT (seen as 15 failing FORL
-- tests). Unwrapped 64-bit arithmetic mimics the FP mirror on
-- exactly those unreachable entries, which is what the loop
-- tests are calibrated against.
function IRNodeBinOpInt:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, type)
    local data = string.format('(%s %s %s)', self.op_str, left_op, right_op)

    -- LuaJIT's int arithmetic is 32-bit and wraps, so a folded
    -- result is only the real one while it stays in range. Out of
    -- range the node keeps its symbolic form, which is always
    -- sound -- just less folded; the emitted term wraps anyway.
    if self.const_fn then
        local lc = utils.resolve_const(self:get_left_op(), ctx)
        local rc = utils.resolve_const(self:get_right_op(), ctx)
        if lc ~= nil and rc ~= nil then
            local v = self.const_fn(lc, rc)
            if v == math.floor(v) and v >= -2 ^ 31 and v < 2 ^ 31 then
                ctx.const_nums[self:get_ssa_reference()] = v
            end
        end
    end

    if type == 'int' and not self:get_flags().irt_isphi then
        data = arith_utils.wrap_i32(data)
    end
    return ctx.op_stack:store(self:get_ssa_reference(), type, data)
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


-- Integer shift (BSHL/BSHR/BSAR). int values are stored in a
-- 64-bit BV but are semantically int32, so the shift must run
-- at 32-bit width: x86 (and LuaJIT's fold) mask the shift count
-- to the low 5 bits, and only bits 31..0 of the operand
-- participate. Working on the raw 64-bit value with an unmasked
-- count is wrong (e.g. `x << 33` folds to `x << 1`, but bvshl
-- by 33 != bvshl by 1). op_str selects the 32-bit shift:
-- bvshl / bvlshr (logical) / bvashr (arithmetic).
local IRNodeBinOpShiftInt = {}
ir_node.extended(IRNodeBinOpShiftInt, IRNodeBinOpBase)

function IRNodeBinOpShiftInt:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_int_op(self:get_right_op(), ctx, type)
    local val = ('((_ extract 31 0) %s)'):format(left_op)
    -- Mask the shift count to 5 bits (int32 shift semantics).
    local count = ('(bvand ((_ extract 31 0) %s) #x0000001f)'):format(right_op)
    local shifted = ('(%s %s %s)'):format(self.op_str, val, count)
    -- Sign-extend the 32-bit result back to the stored 64-bit
    -- width.
    local data = ('((_ sign_extend 32) %s)'):format(shifted)
    return ctx.op_stack:store(self:get_ssa_reference(), type, data)
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
    BinOpShiftInt = IRNodeBinOpShiftInt,
    BinOpI64 = IRNodeBinOpI64,
    BinOpU32 = IRNodeBinOpU32,
    BinOpGuardNum = IRNodeBinOpGuardNum,
    BinOpGuardInt = IRNodeBinOpGuardInt,
    BinOpGuardI64 = IRNodeBinOpGuardI64,
    BinOpGuardU32 = IRNodeBinOpGuardU32,
}
