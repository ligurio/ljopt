local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

-- Lua `%` floors, so the result takes the divisor's sign -- SMT
-- `bvsmod`, not `bvsrem`. The int MOD the recorder emits comes
-- from Lua `%` and folds through lj_vm_modi, which floors too.
impls.IRNodeMODInt = { op_str = 'bvsmod' }
ir_node.extended(impls.IRNodeMODInt, bin_op.BinOpInt)

impls.IRNodeMODI64 = { op_str = 'bvsrem' }
ir_node.extended(impls.IRNodeMODI64, bin_op.BinOpI64)

-- See DIV: u64 takes the unsigned remainder.
impls.IRNodeMODU64 = { op_str = 'bvurem' }
ir_node.extended(impls.IRNodeMODU64, bin_op.BinOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
