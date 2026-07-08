local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSHRI64 = { op_str = 'bvashr' }
ir_node.extended(impls.IRNodeBSHRI64, bin_op.BinOpI64)

-- BSHR is LuaJIT's bit.rshift: a *logical* (unsigned) right
-- shift, so bvlshr, not bvashr. (BSAR is the arithmetic one.)
impls.IRNodeBSHRInt = { op_str = 'bvlshr' }
ir_node.extended(impls.IRNodeBSHRInt, bin_op.BinOpShiftInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
