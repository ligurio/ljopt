local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

-- BSHR is LuaJIT's bit.rshift: a *logical* (unsigned) right
-- shift, so bvlshr, not bvashr. (BSAR is the arithmetic one.)
-- The backend emits SHR for BSHR at every width, so this holds
-- for the 64-bit variants too -- the i64 case said bvashr, which
-- disagreed with the int case on any value with the top bit set.
impls.IRNodeBSHRI64 = { op_str = 'bvlshr' }
ir_node.extended(impls.IRNodeBSHRI64, bin_op.BinOpShiftI64)

impls.IRNodeBSHRU64 = { op_str = 'bvlshr' }
ir_node.extended(impls.IRNodeBSHRU64, bin_op.BinOpShiftI64)

impls.IRNodeBSHRInt = { op_str = 'bvlshr' }
ir_node.extended(impls.IRNodeBSHRInt, bin_op.BinOpShiftInt)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
