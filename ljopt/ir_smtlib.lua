-- IR to SMT-LIB
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR

-- IR Types blacklist.
local ir_types_bl = {
    ["nil"] = false,
    ["fal"] = false,
    ["tru"] = false,
    ["lud"] = false,
    ["str"] = false,
    ["p32"] = false,
    ["thr"] = false,
    ["pro"] = false,
    ["fun"] = false,
    ["p64"] = false,
    ["cdt"] = false,
    ["tab"] = false,
    ["udt"] = false,
    ["flt"] = false,
    ["num"] = false,
    ["i8"] = false,
    ["u8"] = false,
    ["i16"] = false,
    ["u16"] = false,
    ["int"] = false,
    ["u32"] = false,
    ["i64"] = false,
    ["u64"] = false,
    ["sfp"] = false,
}

-- IR instructions blacklist.
local ir_ins_bl = {
    -- Constants.
    ["KPRI"] = false,
    ["KINT"] = false,
    ["KGC"] = false,
    ["KPTR"] = false,
    ["KKPTR"] = false,
    ["KNULL"] = false,
    ["KNUM"] = false,
    ["KINT64"] = false,
    ["KSLOT"] = false,
    -- Guarded Assertions.
    ["OP"] = false,
    ["LT"] = false,
    ["GE"] = false,
    ["LE"] = false,
    ["GT"] = false,
    ["ULT"] = false,
    ["UGE"] = false,
    ["ULE"] = false,
    ["UGT"] = false,
    ["EQ"] = false,
    ["NE"] = false,
    ["ABC"] = false,
    ["RETF"] = false,
    -- Bit Ops.
    ["BNOT"] = false,
    ["BSWAP"] = false,
    ["BAND"] = false,
    ["BOR"] = false,
    ["BXOR"] = false,
    ["BSHL"] = false,
    ["BSHR"] = false,
    ["BSAR"] = false,
    ["BROL"] = false,
    ["BROR"] = false,
    -- Arithmetic Ops.
    ["ADD"] = false,
    ["SUB"] = false,
    ["MUL"] = false,
    ["DIV"] = false,
    ["MOD"] = false,
    ["POW"] = false,
    ["NEG"] = false,
    ["ABS"] = false,
    ["ATAN2"] = false,
    ["LDEXP"] = false,
    ["MIN"] = false,
    ["MAX"] = false,
    ["FPMATH"] = false,
    ["ADDOV"] = false,
    ["SUBOV"] = false,
    ["MULOV"] = false,
    ["FPM_FLOOR"] = false,
    ["FPM_CEIL"] = false,
    ["FPM_TRUNC"] = false,
    ["FPM_SQRT"] = false,
    ["FPM_EXP"] = false,
    ["FPM_EXP2"] = false,
    ["FPM_LOG"] = false,
    ["FPM_LOG2"] = false,
    ["FPM_LOG10"] = false,
    ["FPM_SIN"] = false,
    ["FPM_COS"] = false,
    ["FPM_TAN"] = false,
    -- Memory References.
    ["AREF"] = false,
    ["HREFK"] = false,
    ["HREF"] = false,
    ["NEWREF"] = false,
    ["UREFO"] = false,
    ["UREFC"] = false,
    ["FREF"] = false,
    ["STRREF"] = false,
    -- Loads and Stores.
    ["ALOAD"] = false,
    ["HLOAD"] = false,
    ["ULOAD"] = false,
    ["FLOAD"] = false,
    ["XLOAD"] = false,
    ["SLOAD"] = false,
    ["VLOAD"] = false,
    ["ASTORE"] = false,
    ["HSTORE"] = false,
    ["USTORE"] = false,
    ["FSTORE"] = false,
    ["XSTORE"] = false,
    -- Allocations.
    ["SNEW"] = false,
    ["XSNEW"] = false,
    ["TNEW"] = false,
    ["TDUP"] = false,
    ["CNEW"] = false,
    ["CNEWI"] = false,
    -- Barriers.
    ["TBAR"] = false,
    ["OBAR"] = false,
    ["XBAR"] = false,
    -- Type Conversions.
    ["CONV"] = false,
    ["TOBIT"] = false,
    ["TOSTR"] = false,
    ["STRTO"] = false,
    -- Calls.
    ["CALLN"] = false,
    ["CALLL"] = false,
    ["CALLS"] = false,
    ["CALLXS"] = false,
    ["CARG"] = false,
    -- Miscellaneous Ops.
    ["NOP"] = false,
    ["BASE"] = false,
    ["PVAL"] = false,
    ["GCSTEP"] = false,
    ["HIOP"] = false,
    ["LOOP"] = false,
    ["USE"] = false,
    ["PHI"] = false,
    ["RENAME"] = false,
}

local function is_supported_ir_ins(ins)
    return ir_ins_bl[ins] == true
end

local function is_supported_ir_type(tp)
    return ir_types_bl[tp] == true
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
