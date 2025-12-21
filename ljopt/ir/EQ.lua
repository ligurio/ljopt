local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeEQBase = {}
ir_node.extended(IRNodeEQBase, ir_node.ir_node_base)

local impls = {}

-- At least Z3 and Bitwuzla expect `=` for floating point
-- comparison.
impls.IRNodeEQNum = { op_str = '=' }
ir_node.extended(impls.IRNodeEQNum, bin_op.BinOpGuardNum)

impls.IRNodeEQInt = { op_str = '=' }
ir_node.extended(impls.IRNodeEQInt, bin_op.BinOpGuardInt)

impls.IRNodeEQI64 = { op_str = '=' }
ir_node.extended(impls.IRNodeEQI64, bin_op.BinOpGuardI64)

impls.IRNodeEQTab = {}
ir_node.extended(impls.IRNodeEQTab, IRNodeEQBase)

function impls.IRNodeEQTab:to_smt_lib(--[[ctx]])
    -- TODO: Implement.
    return ''
end

impls.IRNodeEQFun = {}
ir_node.extended(impls.IRNodeEQFun, IRNodeEQBase)

function impls.IRNodeEQFun:to_smt_lib()
    -- TODO: Implement.
    return ''
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
