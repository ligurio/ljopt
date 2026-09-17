local opcodes = require("ljopt.irfuzz.opcodes")
local opcode_class = require("ljopt.irfuzz.opcode_class")

local T = {}
for i, name in ipairs(opcodes.types) do T[name] = i - 1 end

local GUARD = 0x80

local K = { NONE = 0, REF = 1, KINT = 2, KNUM = 3, LIT = 4, KINT64 = 5,
            KSTR = 6 }

local INT_LIKE = { T.INT, T.I64 }
local UINT_LIKE = { T.U32, T.U64 }
local NUMERIC = { T.NUM, T.INT, T.I64 }

local function ref(types) return { kind = "ref", types = types } end
local function value(types) return { kind = "value", types = types } end
local function lit(pool) return { kind = "lit", pool = pool } end
local function same() return { kind = "same" } end
local function same_value() return { kind = "same_value" } end
local function none() return { kind = "none" } end

local SHIFT_COUNTS = { 0, 1, 7, 31, 32, 63, 65 }
local FPMATH_MODES = { 0, 1, 2, 3 }
local LDEXP_EXPS = { -2, -1, 0, 1, 2, 8 }

local SIG = {}

local function sig(names, spec)
    for name in names:gmatch("%S+") do
        assert(SIG[name] == nil, "duplicate signature: " .. name)
        assert(opcodes.by_name[name], "no such opcode: " .. name)
        SIG[name] = spec
    end
end

-- Compares are guards: the result type carries IRT_GUARD and the
-- instruction yields no value.
sig("LT GE LE GT EQ NE", {
    types = NUMERIC, guard = true, cmp = true,
    op1 = same(), op2 = same_value(),
})
-- ULT/UGE/ULE/UGT compare u32/u64 values, and nothing in this
-- tranche produces one: int<->u32 CONV is dead on x64, so a u32
-- only ever enters a trace through XLOAD of an unsigned C field.
-- They are signed off with the memory ops, not here.

sig("ADD SUB MUL", { types = NUMERIC, op1 = same(), op2 = same_value() })
sig("MIN MAX", { types = { T.NUM }, op1 = same(), op2 = same_value() })
sig("NEG", { types = { T.NUM, T.INT }, op1 = same(), op2 = none() })
sig("ABS", { types = { T.NUM }, op1 = same(), op2 = none() })

-- num DIV only, and no MOD at all. gen.lua's RECORDER_IMPOSSIBLE
-- records why: lj_opt_narrow_mod means a num MOD never reaches
-- the IR, and int DIV/MOD are lowered away before it too. POW is
-- left out for the other reason in that file -- ljopt models it
-- uninterpreted, so the x^2 fold reads as a miscompile.
sig("DIV", { types = { T.NUM }, op1 = same(), op2 = same_value() })

sig("FPMATH", { types = { T.NUM }, op1 = same(), op2 = lit(FPMATH_MODES) })
sig("LDEXP", { types = { T.NUM }, op1 = same(),
               op2 = { kind = "knum", pool = LDEXP_EXPS } })

sig("BAND BOR BXOR", { types = INT_LIKE, op1 = same(), op2 = same_value() })
sig("BNOT BSWAP", { types = INT_LIKE, op1 = same(), op2 = none() })
-- Shift counts are always KINT, whatever the width being shifted:
-- LJFOLD matches on `BSHL KINT64 KINT`.
sig("BSHL BSHR BSAR BROL BROR", {
    types = INT_LIKE, op1 = same(),
    op2 = { kind = "kint", pool = SHIFT_COUNTS },
})

sig("ADDOV SUBOV MULOV", {
    types = { T.INT }, guard = true, op1 = same(), op2 = same_value(),
})

sig("TOBIT", { types = { T.INT }, op1 = ref({ T.NUM }), op2 = none() })

-- CONV is what makes the wider types reachable at all: without it
-- nothing ever produces an i64, so every i64 signature below is
-- dead. Mode = (dst<<IRCONV_DSH)|src, plus IRCONV_SEXT for a
-- signed widen and IRCONV_ANY for num->int. IRCONV_DSH = 5.
-- Both num->integer modes carry IRCONV_ANY, the plain C
-- truncation. The guarded modes (INDEX/CHECK) are the ones
-- enum.lua's NARROW_SINKS rules out for i64: every guarded
-- num->integer CONV LuaJIT emits is IRCONV_INT_NUM through IRTGI,
-- so a guarded i64 sink narrows to an i64 ADDOV that no emit site
-- produces, and the two levels then disagree about the exit.
local SEXT, ANY = 0x800, 0x1000
local CONV_MODES = {
    [T.I64] = { { T.I64 * 32 + T.INT + SEXT, { T.INT } },
                { T.I64 * 32 + T.NUM + ANY, { T.NUM } } },
    [T.INT] = { { T.INT * 32 + T.NUM + ANY, { T.NUM } },
                { T.INT * 32 + T.I64, { T.I64 } } },
    [T.NUM] = { { T.NUM * 32 + T.INT, { T.INT } },
                { T.NUM * 32 + T.I64, { T.I64 } } },
}
sig("CONV", {
    types = { T.I64, T.INT, T.NUM },
    conv = CONV_MODES,
    op1 = { kind = "conv_src" }, op2 = { kind = "conv_mode" },
})

-- Array indices and hash keys have to come from disjoint ranges.
-- LuaJIT keeps a table's array part and hash part in separate
-- address spaces and the recorder reaches a key through only one
-- of them, but ljopt models both as make_tab_ref(tab, key): the
-- same value used for an element and a slot aliases in the SMT
-- and reads as a store-to-load conflict. Positive for the array,
-- negative for the hash, exactly as gen.lua splits them.
local ARR_IDXS = { 1, 2, 3, 4, 5 }
local HASH_KEYS = { -1, -2, -3, -7 }

local IRFL_TAB_ARRAY = 6

local function from(op, types)
    return { kind = "ref", types = types, from = { [op] = true } }
end

sig("FLOAD", {
    types = { T.P32 }, tab_field = true,
    op1 = ref({ T.TAB }), op2 = lit({ IRFL_TAB_ARRAY }),
})

-- AREF indexes the array part, so its op1 is the FLOAD of
-- tab.array and never the table itself -- the same shape rule that
-- makes lj_opt_fwd_hrefk read fleft->op1 as a table.
sig("AREF", {
    types = { T.P32 },
    op1 = from("FLOAD", { T.P32 }),
    op2 = { kind = "kint", pool = ARR_IDXS },
})
sig("HREF", {
    types = { T.P32 },
    op1 = ref({ T.TAB }),
    op2 = { kind = "kint", pool = HASH_KEYS },
})

-- Every ALOAD/HLOAD the recorder emits is a guard: it type-checks
-- the loaded value. Unguarded ones are recorder-impossible and
-- were the source of the --tables false SATs -- lj_opt_dse_ahstore
-- bails on an intervening guard, so without one DSE deletes a
-- store across a load and the optimized trace reads another value.
sig("ALOAD", {
    types = { T.NUM }, guard = true,
    op1 = from("AREF", { T.P32 }), op2 = none(),
})
sig("HLOAD", {
    types = { T.NUM }, guard = true,
    op1 = from("HREF", { T.P32 }), op2 = none(),
})

sig("ASTORE", {
    types = { T.NUM }, store = true,
    op1 = from("AREF", { T.P32 }), op2 = value({ T.NUM }),
})
sig("HSTORE", {
    types = { T.NUM }, store = true,
    op1 = from("HREF", { T.P32 }), op2 = value({ T.NUM }),
})

local missing = {}
for _, name in ipairs(opcode_class.emit) do
    if SIG[name] == nil then missing[#missing + 1] = name end
end
table.sort(missing)

local covered = {}
for name in pairs(SIG) do covered[#covered + 1] = name end
table.sort(covered)

return {
    T = T,
    K = K,
    GUARD = GUARD,
    IRFL_TAB_ARRAY = IRFL_TAB_ARRAY,
    ARR_IDXS = ARR_IDXS,
    HASH_KEYS = HASH_KEYS,
    sig = SIG,
    covered = covered,
    missing = missing,
}
