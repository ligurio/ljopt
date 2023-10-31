-- IR to SMT-LIB
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR

-- IR Types blacklist
local ir_types_bl = {
    -- nil
	-- fal
	-- tru
	-- lud
	-- str
	-- p32
	-- thr
	-- pro
	-- fun
	-- p64
	-- cdt
	-- tab
	-- udt
	-- flt
	-- num
	-- i8
	-- u8
	-- i16
	-- u16
	-- int
	-- u32
	-- i64
	-- u64
	-- sfp
}

-- IR instructions blacklist

local ir_ins_bl = {
    -- Constants
	-- KPRI
	-- KINT
	-- KGC
	-- KPTR
	-- KKPTR
	-- KNULL
	-- KNUM
	-- KINT64
	-- KSLOT

	-- Guarded Assertions
	-- OP
	-- LT
	-- GE
	-- LE
	-- GT
	-- ULT
	-- UGE
	-- ULE
	-- UGT
	-- EQ
	-- NE
	-- ABC
	-- RETF

	-- Bit Ops
	-- BNOT
	-- BSWAP
	-- BAND
	-- BOR
	-- BXOR
	-- BSHL
	-- BSHR
	-- BSAR
	-- BROL
	-- BROR

	-- Arithmetic Ops
	-- ADD
	-- SUB
	-- MUL
	-- DIV
	-- MOD
	-- POW
	-- NEG
	-- ABS
	-- ATAN2
	-- LDEXP
	-- MIN
	-- MAX
	-- FPMATH
	-- ADDOV
	-- SUBOV
	-- MULOV
	-- FPM_FLOOR
	-- FPM_CEIL
	-- FPM_TRUNC
	-- FPM_SQRT
	-- FPM_EXP
	-- FPM_EXP2
	-- FPM_LOG
	-- FPM_LOG2
	-- FPM_LOG10
	-- FPM_SIN
	-- FPM_COS
	-- FPM_TAN

	-- Memory References
	-- AREF
	-- HREFK
	-- HREF
	-- NEWREF
	-- UREFO
	-- UREFC
	-- FREF
	-- STRREF

	-- Loads and Stores
	-- ALOAD
	-- HLOAD
	-- ULOAD
	-- FLOAD
	-- XLOAD
	-- SLOAD
	-- VLOAD
	-- ASTORE
	-- HSTORE
	-- USTORE
	-- FSTORE
	-- XSTORE

	-- Allocations
	-- SNEW
	-- XSNEW
	-- TNEW
	-- TDUP
	-- CNEW
	-- CNEWI

	-- Barriers
	-- TBAR
	-- OBAR
	-- XBAR

	-- Type Conversions
	-- CONV
	-- TOBIT
	-- TOSTR
	-- STRTO

	-- Calls
	-- CALLN
	-- CALLL
	-- CALLS
	-- CALLXS
	-- CARG

	-- Miscellaneous Ops
	-- NOP
	-- BASE
	-- PVAL
	-- GCSTEP
	-- HIOP
	-- LOOP
	-- USE
	-- PHI
	-- RENAME
}

return {
}
