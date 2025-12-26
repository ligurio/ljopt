--[[
Provides mapping between IR node opcodes and their translators.
]]--

local dev_checks = require('ljopt.dev_checks')
local ir_node_dummy = require('ljopt.ir.ir_node_dummy')

local ir_node_ADDOV = require('ljopt.ir.ADDOV')
local ir_node_ADD = require('ljopt.ir.ADD')
local ir_node_BAND = require('ljopt.ir.BAND')
local ir_node_BROL = require('ljopt.ir.BROL')
local ir_node_CONV = require('ljopt.ir.CONV')
local ir_node_DIV = require('ljopt.ir.DIV')
local ir_node_EQ = require('ljopt.ir.EQ')
local ir_node_FLOAD = require('ljopt.ir.FLOAD')
local ir_node_LE = require('ljopt.ir.LE')
local ir_node_MUL = require('ljopt.ir.MUL')
local ir_node_NEG = require('ljopt.ir.NEG')
local ir_node_NE = require('ljopt.ir.NE')
local ir_node_NOP = require('ljopt.ir.NOP')
local ir_node_SLOAD = require('ljopt.ir.SLOAD')
local ir_node_SUB = require('ljopt.ir.SUB')
local ir_node_ULE = require('ljopt.ir.ULE')

local opcodes_table = {
    -- Constants.
    ['KPRI'] = false,
    ['KINT'] = false,
    ['KGC'] = false,
    ['KPTR'] = false,
    ['KKPTR'] = false,
    ['KNULL'] = false,
    ['KNUM'] = false,
    ['KINT64'] = false,
    ['KSLOT'] = false,
    -- Guarded Assertions.
    ['OP'] = false,
    ['LT'] = false,
    ['GE'] = false,
    ['LE'] = ir_node_LE,
    ['GT'] = false,
    ['ULT'] = false,
    ['UGE'] = false,
    ['ULE'] = ir_node_ULE,
    ['UGT'] = false,
    ['EQ'] = ir_node_EQ,
    ['NE'] = ir_node_NE,
    ['ABC'] = ir_node_dummy,
    ['RETF'] = false,
    -- Bit Ops.
    ['BNOT'] = false,
    ['BSWAP'] = false,
    ['BAND'] = ir_node_BAND,
    ['BOR'] = false,
    ['BXOR'] = false,
    ['BSHL'] = false,
    ['BSHR'] = false,
    ['BSAR'] = false,
    ['BROL'] = ir_node_BROL,
    ['BROR'] = false,
    -- Arithmetic Ops.
    ['ADD'] = ir_node_ADD,
    ['SUB'] = ir_node_SUB,
    ['MUL'] = ir_node_MUL,
    ['DIV'] = ir_node_DIV,
    ['MOD'] = false,
    ['POW'] = false,
    ['NEG'] = ir_node_NEG,
    ['ABS'] = false,
    ['ATAN2'] = false,
    ['LDEXP'] = false,
    ['MIN'] = false,
    ['MAX'] = false,
    ['FPMATH'] = false,
    ['ADDOV'] = ir_node_ADDOV,
    ['SUBOV'] = false,
    ['MULOV'] = false,
    ['FPM_FLOOR'] = false,
    ['FPM_CEIL'] = false,
    ['FPM_TRUNC'] = false,
    ['FPM_SQRT'] = false,
    ['FPM_EXP'] = false,
    ['FPM_EXP2'] = false,
    ['FPM_LOG'] = false,
    ['FPM_LOG2'] = false,
    ['FPM_LOG10'] = false,
    ['FPM_SIN'] = false,
    ['FPM_COS'] = false,
    ['FPM_TAN'] = false,
    -- Memory References.
    ['AREF'] = ir_node_dummy,
    ['HREFK'] = ir_node_dummy,
    ['HREF'] = false,
    ['NEWREF'] = ir_node_dummy,
    ['UREFO'] = false,
    ['UREFC'] = ir_node_dummy,
    ['FREF'] = false,
    ['STRREF'] = false,
    -- Loads and Stores.
    ['ALOAD'] = false,
    ['HLOAD'] = ir_node_dummy,
    ['ULOAD'] = false,
    ['FLOAD'] = ir_node_FLOAD,
    ['XLOAD'] = false,
    ['SLOAD'] = ir_node_SLOAD,
    ['VLOAD'] = false,
    ['ASTORE'] = ir_node_dummy,
    ['HSTORE'] = ir_node_dummy,
    ['USTORE'] = false,
    ['FSTORE'] = false,
    ['XSTORE'] = false,
    -- Allocations.
    ['SNEW'] = false,
    ['XSNEW'] = false,
    ['TNEW'] = false,
    ['TDUP'] = false,
    ['CNEW'] = false,
    ['CNEWI'] = ir_node_dummy,
    -- Barriers.
    ['TBAR'] = false,
    ['OBAR'] = false,
    ['XBAR'] = false,
    -- Type Conversions.
    ['CONV'] = ir_node_CONV,
    ['TOBIT'] = false,
    ['TOSTR'] = false,
    ['STRTO'] = false,
    -- Calls.
    ['CALLN'] = false,
    ['CALLL'] = false,
    ['CALLS'] = false,
    ['CALLXS'] = false,
    ['CARG'] = false,
    -- Miscellaneous Ops.
    ['SNAP'] = ir_node_dummy,
    ['NOP'] = ir_node_NOP,
    ['BASE'] = false,
    ['PVAL'] = false,
    ['GCSTEP'] = false,
    ['HIOP'] = false,
    ['LOOP'] = ir_node_dummy,
    ['USE'] = false,
    ['PHI'] = ir_node_dummy,
    ['RENAME'] = false,
}

local function get_all_count()
    local count = 0
    for _ in pairs(opcodes_table) do count = count + 1 end
    return count
end

local function get_supported_count()
    local supported_count = 0
    for _, v in pairs(opcodes_table) do
        if v and v.is_dummy_node then
            supported_count = supported_count + 1
        end
    end
    return supported_count
end

local function get_unsupported_count()
    return get_all_count() - get_supported_count()
end

local function instance(ssa_ref, flags, type, opcode, left_op, right_op)
    dev_checks('string', 'string', '?string', 'string', '?string', '?string')

    assert(opcodes_table[opcode], 'Unsupported operation ' .. opcode)
    return opcodes_table[opcode].instance(
        ssa_ref, flags, type, left_op, right_op
    )
end

return {
    instance = instance,
    get_supported_count = get_supported_count,
    get_unsupported_count = get_unsupported_count,
    get_all_count = get_all_count,
}
