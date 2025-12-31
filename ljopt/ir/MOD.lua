local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMODNum = {}
ir_node.extended(impls.IRNodeMODNum, bin_op.BinOpNum)

impls.IRNodeMODInt = {}
ir_node.extended(impls.IRNodeMODInt, bin_op.BinOpInt)

impls.IRNodeMODI64 = {}
ir_node.extended(impls.IRNodeMODI64, bin_op.BinOpI64)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['int'] = 'bvsrem',
        ['i64'] = 'bvsrem',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'MOD', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
