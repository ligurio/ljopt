local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeNEInt = { op_str = 'distinct' }
ir_node.extended(impls.IRNodeNEInt, bin_op.BinOpGuardInt)

impls.IRNodeNEU32 = { op_str = 'distinct' }
ir_node.extended(impls.IRNodeNEU32, bin_op.BinOpGuardU32)

impls.IRNodeNENum = {}
ir_node.extended(impls.IRNodeNENum, ir_node.ir_node_base)

function impls.IRNodeNENum:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_num_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local right_op = ir_node.retrieve_num_op(
        self:get_right_op(), ctx, self:get_type()
    )
    local data = string.format('(not (fp.eq %s %s))',
        left_op, right_op
    )
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

impls.IRNodeNEI64 = { op_str = 'distinct' }
ir_node.extended(impls.IRNodeNEI64, bin_op.BinOpGuardI64)

-- `NE tab.meta NULL` -- the mirror of EQ tab, asserting a
-- metatable *is* present. See IRNodeEQTab for why the id of a
-- nil field is NULL and needs nothing declared.
impls.IRNodeNETab = {}
ir_node.extended(impls.IRNodeNETab, ir_node.ir_node_base)

function impls.IRNodeNETab:to_smt_lib(ctx)
    local left = ctx.op_stack:load(self:get_left_op():get_ssa(), 'tab')
    return ctx.te_stack:store(self:get_ssa_reference(),
        ('(not (= %s (tab_uid nil-val)))'):format(left))
end

function impls.IRNodeNETab.is_implemented(_flags, _type, _opcode,
                                          left_op, right_op_val)
    return left_op ~= nil and left_op:is_ssa()
        and op_type.to_string(right_op_val) == 'NULL'
end

impls.IRNodeNEStr = {}
ir_node.extended(impls.IRNodeNEStr, ir_node.ir_node_base)

function impls.IRNodeNEStr:to_smt_lib(ctx)
    return ctx.te_stack:store(self:get_ssa_reference(),
        ('(not (= %s %s))'):format(
            ir_node.retrieve_str_op(self:get_left_op(), ctx),
            ir_node.retrieve_str_op(self:get_right_op(), ctx)
        ))
end
impls.IRNodeNEU64 = { op_str = 'distinct' }
ir_node.extended(impls.IRNodeNEU64, bin_op.BinOpGuardI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
