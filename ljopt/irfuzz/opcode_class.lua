local opcodes = require('ljopt.irfuzz.opcodes')

local EMIT = {
    'LT', 'GE', 'LE', 'GT', 'ULT', 'UGE', 'ULE', 'UGT', 'EQ', 'NE', 'ABC',
    'BNOT', 'BSWAP', 'BAND', 'BOR', 'BXOR', 'BSHL', 'BSHR', 'BSAR', 'BROL',
    'BROR', 'ADD', 'SUB', 'MUL', 'DIV', 'MOD', 'POW', 'NEG', 'ABS', 'LDEXP',
    'MIN', 'MAX', 'FPMATH', 'ADDOV', 'SUBOV', 'MULOV', 'AREF', 'HREF',
    'NEWREF', 'UREFO', 'UREFC', 'FREF', 'STRREF', 'ALOAD', 'HLOAD', 'ULOAD',
    'FLOAD', 'XLOAD', 'SLOAD', 'ASTORE', 'HSTORE', 'USTORE', 'FSTORE',
    'XSTORE', 'SNEW', 'TNEW', 'CNEW', 'BUFHDR', 'BUFPUT', 'BUFSTR', 'TBAR',
    'CONV', 'TOBIT', 'TOSTR', 'CALLN', 'CALLL', 'CARG',
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

local class = {}
local function mark(names, kind)
    for _, name in ipairs(names) do
        assert(class[name] == nil, 'opcode listed twice: ' .. name)
        class[name] = kind
    end
end

mark(EMIT, 'emit')
mark(CONST, 'const')
mark(BACKEND, 'backend')
mark(LOOP, 'loop')
mark(TODO, 'todo')

local unclassified, stale, counts = {}, {}, {}
for _, op in ipairs(opcodes.ops) do
    local kind = class[op.name]
    if kind == nil then
        unclassified[#unclassified + 1] = op.name
    else
        counts[kind] = (counts[kind] or 0) + 1
    end
end
for name in pairs(class) do
    if opcodes.by_name[name] == nil then stale[#stale + 1] = name end
end
table.sort(stale)

return {
    class = class,
    counts = counts,
    unclassified = unclassified,
    stale = stale,
    emit = EMIT,
    const = CONST,
    backend = BACKEND,
    loop = LOOP,
    todo = TODO,
}
