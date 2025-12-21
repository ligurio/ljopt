local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeEQBase = {}
ir_node.extended(IRNodeEQBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeEQNum = {}
ir_node.extended(impls.IRNodeEQNum, bin_op.BinOpGuardNum)

impls.IRNodeEQInt = {}
ir_node.extended(impls.IRNodeEQInt, bin_op.BinOpGuardInt)

impls.IRNodeEQI64 = {}
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

local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['tab'] = 'Tab',
        ['fun'] = 'Fun',
        ['num'] = 'Num',
        ['i8'] = false,
        ['u8'] = false,
        ['i16'] = false,
        ['u16'] = false,
        ['int'] = 'Int',
        ['u32'] = false,
        ['i64'] = 'I64',
        ['u64'] = false,
        ['sfp'] = false,
    }
    -- At least Z3 and Bitwuzla expect `=` for floating point
    -- comparison.
    local op_table = {
        ['num'] = '=',
        ['int'] = '=',
        ['i64'] = '=',
    }
    assert(type_table[type], 'Unsupported type for EQ operation ' .. type)
    local node = impls['IRNodeEQ' .. type_table[type]]:new(
        ssa_ref, flags, type, 'EQ', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
