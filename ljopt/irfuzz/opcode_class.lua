local opcodes = require('ljopt.irfuzz.opcodes')

local EMIT = {
    'LT', 'GE', 'LE', 'GT', 'ULT', 'UGE', 'ULE', 'UGT', 'EQ', 'NE', 'ABC',
    'BNOT', 'BSWAP', 'BAND', 'BOR', 'BXOR', 'BSHL', 'BSHR', 'BSAR', 'BROL',
    'BROR', 'ADD', 'SUB', 'MUL', 'DIV', 'NEG', 'ABS', 'LDEXP',
    'MIN', 'MAX', 'FPMATH', 'ADDOV', 'SUBOV', 'MULOV', 'AREF', 'HREF',
    'NEWREF', 'UREFO', 'UREFC', 'FREF', 'ALOAD', 'HLOAD', 'ULOAD',
    'FLOAD', 'XLOAD', 'SLOAD', 'ASTORE', 'HSTORE', 'USTORE', 'FSTORE',
    'XSTORE', 'TNEW', 'TBAR',
    'CONV', 'TOBIT', 'CALLN', 'CALLL', 'CARG',
}

-- LuaJIT emits these, but ljopt cannot model them soundly yet, so
-- a generator that produced one would report a miscompile that is
-- really a hole in the oracle. Each is recorded where the hole is:
--   MOD, POW          gen.lua RECORDER_IMPOSSIBLE and
--                     KNOWN_LJOPT_GAP -- num MOD and int DIV/MOD
--                     never reach the IR, POW is uninterpreted
--   SNEW, STRREF,
--   TOSTR             enum.lua iter_strops -- SNEW's clamped length
--                     disagrees with fload_str_len_snew, 6 of 45
--                     traces come back SAT on that alone
--   BUFHDR, BUFPUT,
--   BUFSTR            enum.lua iter_bufcalls leaves the BUFSTR a gap
--   CNEW              cdata.ctypeid differs across the two levels
--                     (129 vs 317), the gap that blocks lj_1244
local UNMODELLED = {
    'MOD', 'POW', 'SNEW', 'STRREF', 'TOSTR', 'BUFHDR', 'BUFPUT', 'BUFSTR',
    'CNEW',
}

local CONST = {
    'KPRI', 'KINT', 'KGC', 'KPTR', 'KKPTR', 'KNULL', 'KNUM', 'KINT64', 'KSLOT',
}

local BACKEND = {
    'BASE', 'PVAL', 'GCSTEP', 'HIOP', 'RENAME', 'PROF', 'USE', 'LREF',
}

local LOOP = { 'LOOP', 'PHI' }

local TODO = {
    'CALLA', 'CALLS', 'CALLXS', 'CNEWI', 'HREFK', 'NOP', 'OBAR', 'RETF',
    'STRTO', 'TDUP', 'VLOAD', 'XBAR', 'XSNEW',
}

local TYPE_EMIT = {
    'NIL', 'STR', 'P32', 'FUNC', 'P64', 'CDATA', 'TAB', 'FLOAT', 'NUM',
    'I8', 'U8', 'I16', 'U16', 'INT', 'U32', 'I64', 'U64',
}

local TYPE_TODO = {
    'FALSE', 'TRUE', 'LIGHTUD', 'THREAD', 'PROTO', 'UDATA',
}

local TYPE_DEAD = { 'SOFTFP' }

local function classify(universe, groups)
    local class, counts = {}, {}
    for kind, names in pairs(groups) do
        for _, name in ipairs(names) do
            assert(class[name] == nil, 'listed twice: ' .. name)
            class[name] = kind
        end
    end

    local unclassified, stale, known = {}, {}, {}
    for _, name in ipairs(universe) do
        known[name] = true
        local kind = class[name]
        if kind == nil then
            unclassified[#unclassified + 1] = name
        else
            counts[kind] = (counts[kind] or 0) + 1
        end
    end
    for name in pairs(class) do
        if not known[name] then stale[#stale + 1] = name end
    end
    table.sort(stale)

    return { class = class, counts = counts,
             unclassified = unclassified, stale = stale }
end

local op_names = {}
for _, op in ipairs(opcodes.ops) do op_names[#op_names + 1] = op.name end

local ops = classify(op_names, {
    emit = EMIT, const = CONST, backend = BACKEND, loop = LOOP,
    todo = TODO, unmodelled = UNMODELLED,
})

local types = classify(opcodes.types, {
    emit = TYPE_EMIT, todo = TYPE_TODO, dead = TYPE_DEAD,
})

return {
    ops = ops,
    types = types,
    class = ops.class,
    counts = ops.counts,
    unclassified = ops.unclassified,
    stale = ops.stale,
    emit = EMIT,
    const = CONST,
    backend = BACKEND,
    loop = LOOP,
    todo = TODO,
}
