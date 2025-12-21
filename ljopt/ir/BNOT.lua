local un_op = require('ljopt.ir.UnOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBNOTInt = {}
ir_node.extended(impls.IRNodeBNOTInt, un_op.UnOpInt)

impls.IRNodeBNOTI64 = {}
ir_node.extended(impls.IRNodeBNOTI64, un_op.UnOpI64)

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['int'] = 'bvnot',
        ['i64'] = 'bvnot',
    }
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BNOT', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
