--[[
    Provides mapping between IR node opcodes and their translators.
]]--

local dev_checks = require('ljopt.dev_checks')
local ir_node_dummy = require('ljopt.ir.ir_node_dummy')

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
    ['LE'] = false,
    ['GT'] = false,
    ['ULT'] = false,
    ['UGE'] = false,
    ['ULE'] = false,
    ['UGT'] = false,
    ['EQ'] = false,
    ['NE'] = false,
    ['ABC'] = false,
    ['RETF'] = false,
    -- Bit Ops.
    ['BNOT'] = false,
    ['BSWAP'] = false,
    ['BAND'] = false,
    ['BOR'] = false,
    ['BXOR'] = false,
    ['BSHL'] = false,
    ['BSHR'] = false,
    ['BSAR'] = false,
    ['BROL'] = false,
    ['BROR'] = false,
    -- Arithmetic Ops.
    ['ADD'] = false,
    ['SUB'] = false,
    ['MUL'] = false,
    ['DIV'] = false,
    ['MOD'] = false,
    ['POW'] = false,
    ['NEG'] = false,
    ['ABS'] = false,
    ['ATAN2'] = false,
    ['LDEXP'] = false,
    ['MIN'] = false,
    ['MAX'] = false,
    ['FPMATH'] = false,
    ['ADDOV'] = false,
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
    ['AREF'] = false,
    ['HREFK'] = false,
    ['HREF'] = false,
    ['NEWREF'] = false,
    ['UREFO'] = false,
    ['UREFC'] = false,
    ['FREF'] = false,
    ['STRREF'] = false,
    -- Loads and Stores.
    ['ALOAD'] = false,
    ['HLOAD'] = false,
    ['ULOAD'] = false,
    ['FLOAD'] = false,
    ['XLOAD'] = false,
    ['SLOAD'] = false,
    ['VLOAD'] = false,
    ['ASTORE'] = false,
    ['HSTORE'] = false,
    ['USTORE'] = false,
    ['FSTORE'] = false,
    ['XSTORE'] = false,
    -- Allocations.
    ['SNEW'] = false,
    ['XSNEW'] = false,
    ['TNEW'] = false,
    ['TDUP'] = false,
    ['CNEW'] = false,
    ['CNEWI'] = false,
    -- Barriers.
    ['TBAR'] = false,
    ['OBAR'] = false,
    ['XBAR'] = false,
    -- Type Conversions.
    ['CONV'] = false,
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
    ['SNAP'] = false,
    ['NOP'] = false,
    ['BASE'] = false,
    ['PVAL'] = false,
    ['GCSTEP'] = false,
    ['HIOP'] = false,
    ['LOOP'] = false,
    ['USE'] = false,
    ['PHI'] = false,
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
    return opcodes_table[opcode].instance(ssa_ref, flags, type, left_op, right_op)
end

return {
    instance = instance,
    get_supported_count = get_supported_count,
    get_unsupported_count = get_unsupported_count,
    get_all_count = get_all_count,
}
