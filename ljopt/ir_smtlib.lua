-- Translate IR to SMT-LIB.
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations#ssa-ir-optimizations

-- IR Types blacklist.
local ir_types_bl = {
    ["nil"] = true,
    ["fal"] = true,
    ["tru"] = true,
    ["lud"] = true,
    ["str"] = true,
    ["p32"] = true,
    ["thr"] = true,
    ["pro"] = true,
    ["fun"] = true,
    ["p64"] = true,
    ["cdt"] = true,
    ["tab"] = true,
    ["udt"] = true,
    ["flt"] = true,
    ["num"] = true,
    ["i8"] = true,
    ["u8"] = true,
    ["i16"] = true,
    ["u16"] = true,
    ["int"] = true,
    ["u32"] = true,
    ["i64"] = true,
    ["u64"] = true,
    ["sfp"] = true,
}

-- IR instructions blacklist.
local ir_ins_bl = {
    -- Constants.
    ["KPRI"] = true,
    ["KINT"] = true,
    ["KGC"] = true,
    ["KPTR"] = true,
    ["KKPTR"] = true,
    ["KNULL"] = true,
    ["KNUM"] = true,
    ["KINT64"] = true,
    ["KSLOT"] = true,
    -- Guarded Assertions.
    ["OP"] = true,
    ["LT"] = true,
    ["GE"] = true,
    ["LE"] = true,
    ["GT"] = true,
    ["ULT"] = true,
    ["UGE"] = true,
    ["ULE"] = true,
    ["UGT"] = true,
    ["EQ"] = true,
    ["NE"] = true,
    ["ABC"] = true,
    ["RETF"] = true,
    -- Bit Ops.
    ["BNOT"] = true,
    ["BSWAP"] = true,
    ["BAND"] = true,
    ["BOR"] = true,
    ["BXOR"] = true,
    ["BSHL"] = true,
    ["BSHR"] = true,
    ["BSAR"] = true,
    ["BROL"] = true,
    ["BROR"] = true,
    -- Arithmetic Ops.
    ["ADD"] = true,
    ["SUB"] = true,
    ["MUL"] = true,
    ["DIV"] = true,
    ["MOD"] = true,
    ["POW"] = true,
    ["NEG"] = true,
    ["ABS"] = true,
    ["ATAN2"] = true,
    ["LDEXP"] = true,
    ["MIN"] = true,
    ["MAX"] = true,
    ["FPMATH"] = true,
    ["ADDOV"] = true,
    ["SUBOV"] = true,
    ["MULOV"] = true,
    ["FPM_FLOOR"] = true,
    ["FPM_CEIL"] = true,
    ["FPM_TRUNC"] = true,
    ["FPM_SQRT"] = true,
    ["FPM_EXP"] = true,
    ["FPM_EXP2"] = true,
    ["FPM_LOG"] = true,
    ["FPM_LOG2"] = true,
    ["FPM_LOG10"] = true,
    ["FPM_SIN"] = true,
    ["FPM_COS"] = true,
    ["FPM_TAN"] = true,
    -- Memory References.
    ["AREF"] = true,
    ["HREFK"] = true,
    ["HREF"] = true,
    ["NEWREF"] = true,
    ["UREFO"] = true,
    ["UREFC"] = true,
    ["FREF"] = true,
    ["STRREF"] = true,
    -- Loads and Stores.
    ["ALOAD"] = true,
    ["HLOAD"] = true,
    ["ULOAD"] = true,
    ["FLOAD"] = true,
    ["XLOAD"] = true,
    ["SLOAD"] = true,
    ["VLOAD"] = true,
    ["ASTORE"] = true,
    ["HSTORE"] = true,
    ["USTORE"] = true,
    ["FSTORE"] = true,
    ["XSTORE"] = true,
    -- Allocations.
    ["SNEW"] = true,
    ["XSNEW"] = true,
    ["TNEW"] = true,
    ["TDUP"] = true,
    ["CNEW"] = true,
    ["CNEWI"] = true,
    -- Barriers.
    ["TBAR"] = true,
    ["OBAR"] = true,
    ["XBAR"] = true,
    -- Type Conversions.
    ["CONV"] = true,
    ["TOBIT"] = true,
    ["TOSTR"] = true,
    ["STRTO"] = true,
    -- Calls.
    ["CALLN"] = true,
    ["CALLL"] = true,
    ["CALLS"] = true,
    ["CALLXS"] = true,
    ["CARG"] = true,
    -- Miscellaneous Ops.
    ["NOP"] = true,
    ["BASE"] = true,
    ["PVAL"] = true,
    ["GCSTEP"] = true,
    ["HIOP"] = true,
    ["LOOP"] = true,
    ["USE"] = true,
    ["PHI"] = true,
    ["RENAME"] = true,
}

local function is_supported_ir_ins(ins)
    return ir_ins_bl[ins] == false
end

local function is_supported_ir_type(tp)
    return ir_types_bl[tp] == false
end

local function translate(trace)
    for _, ins in pairs(trace) do
        is_supported_ir_type()
        is_supported_ir_ins(ins)
    end

    return "" -- FIXME
end

return {
    translate = translate,
}
