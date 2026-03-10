local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local IRNodeUnOpBase = {}
ir_node.extended(IRNodeUnOpBase, ir_node.ir_node_base)

local IRNodeUnOpNum = {}
ir_node.extended(IRNodeUnOpNum, IRNodeUnOpBase)

local IRNodeUnOpInt = {}
ir_node.extended(IRNodeUnOpInt, IRNodeUnOpBase)

local IRNodeUnOpI64 = {}
ir_node.extended(IRNodeUnOpI64, IRNodeUnOpBase)

function IRNodeUnOpNum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s)', self.op_str, left_op)

    -- Propagate constant when operand is known.
    if self.const_fn then
        local lc = utils.resolve_const(self:get_left_op(), ctx)
        if lc ~= nil then
            ctx.const_nums[self:get_ssa_reference()] = self.const_fn(lc)
        end
    end

    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function IRNodeUnOpInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s)', self.op_str, left_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function IRNodeUnOpI64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_i64_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s)', self.op_str, left_op)
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local IRNodeUnOpGuardNum = {}
ir_node.extended(IRNodeUnOpGuardNum, IRNodeUnOpBase)

local IRNodeUnOpGuardInt = {}
ir_node.extended(IRNodeUnOpGuardInt, IRNodeUnOpBase)

local IRNodeUnOpGuardI64 = {}
ir_node.extended(IRNodeUnOpGuardI64, IRNodeUnOpBase)

function IRNodeUnOpGuardNum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s)', self.op_str, left_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

function IRNodeUnOpGuardInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s)', self.op_str, left_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

function IRNodeUnOpGuardI64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_i64_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local data = string.format('(%s %s)', self.op_str, left_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

return {
    UnOpNum = IRNodeUnOpNum,
    UnOpInt = IRNodeUnOpInt,
    UnOpI64 = IRNodeUnOpI64,
    UnOpGuardNum = IRNodeUnOpGuardNum,
    UnOpGuardInt = IRNodeUnOpGuardInt,
    UnOpGuardI64 = IRNodeUnOpGuardI64,
}
