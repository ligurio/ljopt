local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeADDNum = {
    op_str = 'fp.add',
    const_fn = function(a, b) return a + b end
}
ir_node.extended(impls.IRNodeADDNum, bin_op.BinOpNum)

impls.IRNodeADDInt = {
    op_str = 'bvadd',
    const_fn = function(a, b) return a + b end
}
ir_node.extended(impls.IRNodeADDInt, bin_op.BinOpInt)

impls.IRNodeADDI64 = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDI64, bin_op.BinOpI64)

impls.IRNodeADDU32 = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDU32, bin_op.BinOpU32)

impls.IRNodeADDP64 = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDP64, bin_op.BinOpI64)

-- The recorder offsets a p32 base by a constant -- frame layout
-- for the vararg region, an alias check for an open upvalue.
-- The offset is not a value the trace computes, so the result
-- still names whatever the base named.
impls.IRNodeADDP32 = {}
ir_node.extended(impls.IRNodeADDP32, ir_node.ir_node_base)

function impls.IRNodeADDP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local ssa_ref = self:get_ssa_reference()
    return ctx.op_stack:store(ssa_ref, op_type.TAB,
        ctx.op_stack:load(left_op:get_ssa(), op_type.TAB))
end

function impls.IRNodeADDP32.is_implemented(_flags, _type, _opcode,
                                           left_op, _right_op)
    return left_op ~= nil and left_op:is_ssa()
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
