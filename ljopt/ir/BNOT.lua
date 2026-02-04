local un_op = require('ljopt.ir.UnOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBNOTInt = { op_str = 'bvnot' }
ir_node.extended(impls.IRNodeBNOTInt, un_op.UnOpInt)

impls.IRNodeBNOTI64 = { op_str = 'bvnot' }
ir_node.extended(impls.IRNodeBNOTI64, un_op.UnOpI64)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
