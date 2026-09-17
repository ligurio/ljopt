local opcodes = require("ljopt.irfuzz.opcodes")
local opcode_class = require("ljopt.irfuzz.opcode_class")

local T = {}
for i, name in ipairs(opcodes.types) do T[name] = i - 1 end

local GUARD = 0x80

local K = { NONE = 0, REF = 1, KINT = 2, KNUM = 3, LIT = 4, KINT64 = 5,
            KSTR = 6 }

local INT_LIKE = { T.INT, T.I64 }
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
-- The unsigned compares live with the raw memory ops below:
-- their operand can only come from an XLOAD.

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

-- op2 is a non-zero constant. LJFOLD(ADDOV any KINT) and its SUBOV
-- sibling return LEFTFOLD when that operand is 0, dropping the
-- overflow check -- correctly, since `x - 0` cannot overflow --
-- and the optimized trace then has one exit fewer than the
-- unoptimized one, which the oracle reports as a miscompile. A
-- reference is no safer: `x ^ x` folds to 0 and reaches the same
-- rule, which is what seed 603 did at 12 instructions.
sig("ADDOV SUBOV MULOV", {
    types = { T.INT }, guard = true, ovf = true,
    op1 = same(),
    op2 = { kind = "kint", pool = { 1, -1, 2, 7, -7, 0x7fffffff } },
})

sig("TOBIT", { types = { T.INT }, op1 = ref({ T.NUM }), op2 = none() })

-- A trace may read a stack slot anywhere, not only at entry: the
-- recorder emits an SLOAD the first time a slot is touched, which
-- can be well into the trace. Each one takes a slot of its own --
-- two reads of the same slot at the same type are the same
-- instruction after CSE, and at different types they contradict.
local SLOAD_TYPECHECK = 4
sig("SLOAD", {
    types = { T.NUM, T.INT }, root = true,
    op1 = { kind = "slot" }, op2 = lit({ SLOAD_TYPECHECK }),
})

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

-- Index keys for the bounds check, matching enum.lua's sweep.
local ABC_KEYS = { 1, 3, 5, 100 }

local function from(ops, types)
    local set = {}
    for name in ops:gmatch("%S+") do set[name] = true end
    return { kind = "ref", types = types, from = set }
end

local IRFL_TAB_ASIZE = 8

-- The field literal is decided by the result type: tab.array is a
-- p32 into the array part, tab.asize the int the bounds check
-- reads. One opcode, so the choice rides on the type rather than
-- on a separate signature.
local IRFL_CDATA_INT64 = 17

sig("FLOAD", {
    types = { T.P32, T.INT, T.I64 },
    field_of = { [T.P32] = IRFL_TAB_ARRAY, [T.INT] = IRFL_TAB_ASIZE,
                 [T.I64] = IRFL_CDATA_INT64 },
    op1_of = { [T.P32] = { T.TAB }, [T.INT] = { T.TAB },
               [T.I64] = { T.CDATA } },
    op1 = ref({ T.TAB }), op2 = { kind = "field" },
})

-- Table allocation, guarded because it can fail and exit, and
-- paired so the guard cannot be left dead. The asize/hbits pools
-- are the array-only, hash-only and mixed shapes enum.lua
-- allocates.
sig("TNEW", {
    types = { T.TAB }, guard = true,
    pair_with = { op = "FLOAD", t = T.P32 },
    op1 = { kind = "kint", pool = { 4, 0, 2 } },
    op2 = { kind = "kint", pool = { 0, 2, 1 } },
})

-- NEWREF creates a hash slot, so its key is negative like HREF's
-- and it feeds HSTORE/HLOAD rather than the array ops.
sig("NEWREF", {
    types = { T.P32 },
    op1 = ref({ T.TAB }),
    op2 = { kind = "kint", pool = HASH_KEYS },
})

-- The write barrier yields nothing and takes the table itself.
sig("TBAR", {
    types = { T.NIL }, novalue = true,
    op1 = ref({ T.TAB }), op2 = none(),
})

-- A cdata field ref and the store through it. CNEW is left out:
-- its cdata.ctypeid differs between the two optimization levels
-- (129 vs 317, the gap that blocks lj_1244), so every trace
-- holding one reads as a miscompile.
sig("FREF", {
    types = { T.P64 },
    op1 = ref({ T.CDATA }), op2 = lit({ IRFL_CDATA_INT64 }),
})
sig("FSTORE", {
    types = { T.I64 }, store = true,
    op1 = from("FREF", { T.P64 }), op2 = ref({ T.I64 }),
})

-- ABC checks an index against tab.asize and yields nothing, so
-- like a compare guard it never enters the value pool.
sig("ABC", {
    types = { T.INT }, guard = true, novalue = true,
    op1 = from("FLOAD", { T.INT }),
    op2 = { kind = "kint", pool = ABC_KEYS },
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

-- Upvalue indices paired with their disambiguation hash: the same
-- index under a different hash, and a different index under the
-- same one, so aa_uref has to separate them rather than answering
-- from the index alone.
local UREF_UVS = { 0x011, 0x111, 0x022 }

-- A upvalue ref is a guard that yields a p32, and a p32 is not a
-- value the snapshot can compare, so one nothing reads is dead and
-- DCE takes its exit with it -- the ADDOV failure again. Emitting
-- the ULOAD that consumes it in the same step keeps it live, the
-- way gen.lua pairs an AREF with its access.
sig("UREFO UREFC", {
    types = { T.P32 }, guard = true,
    pair_with = { op = "ULOAD", t = T.NUM },
    op1 = ref({ T.FUNC }), op2 = lit(UREF_UVS),
})
sig("ULOAD", {
    types = { T.NUM }, guard = true,
    op1 = from("UREFO UREFC", { T.P32 }), op2 = none(),
})
sig("USTORE", {
    types = { T.NUM }, store = true,
    op1 = from("UREFO UREFC", { T.P32 }), op2 = value({ T.NUM }),
})

-- Raw FFI memory. An element address is `ADD p64 cdata, k`, which
-- is how the recorder forms one for any `arr[i] = v`, and the
-- narrow C widths only ever reach the IR through XLOAD/XSTORE --
-- LuaJIT promotes them to int for arithmetic.
local XTYPES = { T.I8, T.U8, T.I16, T.U16, T.INT }

-- The store side takes every width, so a narrow store under a
-- wider load exercises the partial-overlap answer in aa_xref. The
-- load side stays int: a narrow result is not a value the final
-- snapshot can carry, and enum.lua's xref sweep reaches those
-- through check.lua's value_outputs path instead of a stack slot.
-- u32 joins int on the load side to feed the unsigned compares.
-- Neither a u32 nor a narrow width can be a snapshot slot, so
-- roots() keeps them out of the comparison on its own.
sig("XLOAD", {
    types = { T.INT, T.U32 },
    op1 = from("ADD", { T.P64 }), op2 = lit({ 0 }),
})
sig("XSTORE", {
    types = XTYPES, store = true,
    op1 = from("ADD", { T.P64 }), op2 = ref({ T.INT }),
})

-- The unsigned compares need a u32, and int<->u32 CONV is dead on
-- x64, so the only source is an XLOAD of an unsigned C field --
-- which is why these arrive with the raw memory ops rather than
-- with the signed compares above.
sig("ULT UGE ULE UGT", {
    types = { T.U32 }, guard = true, cmp = true,
    op1 = from("XLOAD", { T.U32 }),
    op2 = { kind = "kint", pool = { 0, 1, 7, 255, 65535 } },
})


-- The one-argument math calls ljopt models (CALLN.lua's
-- supported_math_fns), by their jit.vmdef.ircall index. That
-- table is 0-based -- ircall[0] is lj_str_cmp -- so walking it
-- with ipairs and subtracting one names the neighbour of every
-- function meant here, which emits calls ljopt does not model and
-- gaps out whatever reads them.
--   36 log10  37 exp  38 sin  39 cos   40 tan  41 asin
--   42 acos   43 atan 44 sinh 45 cosh  46 tanh 54 log
local MATH_CALLS = { 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 54 }

-- atan2 takes both arguments through a CARG pair, which is the
-- only way a CARG reaches a trace here: the other CARG users are
-- the buffer calls, and their BUFSTR is unmodelled.
local IRCALL_ATAN2 = 57

-- op1 has to be a reference. ljopt models these as uninterpreted
-- SMT functions, and LJFOLD(CALLN KNUM any) constant-folds a call
-- on a literal through kfold_fpcall1 -- the optimized side then
-- holds a number the uninterpreted model cannot equate with it,
-- which is exactly the POW gap. A symbolic argument fires no fold
-- rule, so the two sides stay comparable.
-- Its result is not comparable either: ljopt encodes the call as
-- an uninterpreted function, so naming one in the snapshot leaves
-- the oracle with a value it cannot reason about and the checker
-- reports it as a coverage gap. The call still belongs in a trace
-- -- both sides encode the same uninterpreted function, so
-- anything computed from it stays comparable, and the folding
-- around it is exercised.
sig("CALLN", {
    types = { T.NUM }, opaque = true,
    op1 = ref({ T.NUM }), op2 = lit(MATH_CALLS),
})

-- A CARG is the argument pair itself: no value, and the call that
-- consumes it is emitted with it so it cannot be left dangling.
sig("CARG", {
    types = { T.NIL }, novalue = true, carg = true,
    op1 = ref({ T.NUM }), op2 = ref({ T.NUM }),
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
    IRCALL_ATAN2 = IRCALL_ATAN2,
    ARR_IDXS = ARR_IDXS,
    UREF_UVS = UREF_UVS,
    HASH_KEYS = HASH_KEYS,
    sig = SIG,
    covered = covered,
    missing = missing,
}
