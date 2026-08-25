local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local IRNodeEQBase = {}
ir_node.extended(IRNodeEQBase, ir_node.ir_node_base)

local impls = {}

-- At least Z3 and Bitwuzla expect `=` for floating point
-- comparison.
impls.IRNodeEQNum = {}
ir_node.extended(impls.IRNodeEQNum, ir_node.ir_node_base)

function impls.IRNodeEQNum:to_smt_lib(ctx)
    local type = self:get_type()
    local left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, type)
    local right_op = ir_node.retrieve_num_op(self:get_right_op(), ctx, type)
    local data
    -- `x == x` is LuaJIT's NaN guard: in IEEE it is false only
    -- for NaN. SMT-LIB `=` is structural, so `(= x x)` is always
    -- true. Model the self-comparison as an explicit non-NaN
    -- check instead.
    if left_op == right_op then
        data = ('(not (fp.isNaN %s))'):format(left_op)
    else
        data = string.format('(= %s %s)', left_op, right_op)
    end
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

-- `EQ tab.meta NULL`, the guard the recorder puts in front of a
-- table access to prove no metatable can intercept it.
--
-- A field holding no table decodes to `(tab_uid <cell>)`, and
-- tab_uid is a function of the cell, so every nil field already
-- shares one id -- that id *is* NULL, and both traces reach it by
-- congruence. Nothing has to be declared for it.
impls.IRNodeEQTab = {}
ir_node.extended(impls.IRNodeEQTab, ir_node.ir_node_base)

local NULL_TAB = '(tab_uid nil-val)'

function impls.IRNodeEQTab:to_smt_lib(ctx)
    local left = ctx.op_stack:load(self:get_left_op():get_ssa(), 'tab')
    return ctx.te_stack:store(
        self:get_ssa_reference(),
        ('(= %s %s)'):format(left, NULL_TAB)
    )
end

function impls.IRNodeEQTab.is_implemented(_flags, _type, _opcode,
                                          left_op, right_op_val)
    return left_op ~= nil and left_op:is_ssa()
        and op_type.to_string(right_op_val) == 'NULL'
end

-- Interned-string identity. LuaJIT interns strings, so the
-- recorder compares two of them by pointer -- which is equality
-- of the values themselves, the String terms the op stack holds.
impls.IRNodeEQStr = {}
ir_node.extended(impls.IRNodeEQStr, ir_node.ir_node_base)

function impls.IRNodeEQStr:to_smt_lib(ctx)
    return ctx.te_stack:store(self:get_ssa_reference(), ('(= %s %s)'):format(
        ir_node.retrieve_str_op(self:get_left_op(), ctx),
        ir_node.retrieve_str_op(self:get_right_op(), ctx)
    ))
end

-- `EQ REF_BASE, uref + k` is the guard in front of an *open*
-- upvalue: it proves the upvalue still aliases the stack slot
-- the trace was recorded reading, and the recorder then uses the
-- slot directly -- no ULOAD is emitted at all.
--
-- The encoding never relies on that aliasing fact, since the
-- value travels through the slot like any other. Both traces
-- emit the guard and both mean the same thing by it, so it holds
-- here. What is given up is noticing an optimizer that dropped
-- it: REF_BASE has no value in this model to compare against.
impls.IRNodeEQP32 = {}
ir_node.extended(impls.IRNodeEQP32, ir_node.ir_node_base)

local function is_ref_base(op)
    return op ~= nil and op:is_ssa() and op:get_ssa() == 0
end

function impls.IRNodeEQP32:to_smt_lib(ctx)
    return ctx.te_stack:store(self:get_ssa_reference(), 'true')
end

function impls.IRNodeEQP32.is_implemented(_flags, _type, _opcode,
                                          left_op, right_op_val)
    return is_ref_base(left_op) or is_ref_base(right_op_val)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
