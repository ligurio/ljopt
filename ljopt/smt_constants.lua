-- Unfortunately I couldn't find a way yet to implement
-- trace exits for arbitrary length.
local MAXSNAP = 500

-- This variable contains SMT library helpers to be used
-- by ljopt.
--
-- luacheck: push no max_line_length
local LJOPT_SMTLIB = ([[
(define-fun lsb ((x (_ BitVec %d))) (_ BitVec %d) (ite (not (= x (_ bv0 %d))) (_ bv1 %d) (_ bv0 %d)))

(declare-datatypes ((MemCell 0))
  (((int-val (get-bv (_ BitVec 64)))
    (fp-val (get-fp (_ FloatingPoint 11 53)))
    (str-val (get-str String))
    (tab-val (get-tab Int))
    (p32-val (get-p32-tab Int) (get-p32-idx MemCell))
    (nil-val))))
(define-sort MemPtr () (Array Int (Array Int (Array MemCell MemCell))))

; The initial cell-array of a freshly allocated table. Deliberately
; unconstrained rather than ((as const ...) nil-val): cvc5's array
; solver rejects write-chains that connect two constant arrays, and
; a store of a constant key and value into a constant array is
; itself a constant array, so the two trace versions of one table
; produce exactly that shape. Leaving it a plain symbol keeps every
; constant array out of the encoding.
;
; Dropping the all-nil constraint only weakens the formula, and a
; weaker formula can turn unsat into sat, never sat into unsat -- so
; this cannot hide a miscompile, only report a spurious one. Both
; traces read the same symbol, so they agree on whatever it holds.
(declare-fun zero_pointer () (Array MemCell MemCell))

; Uninterpreted functions for TOSTR/STRTO conversions.
(declare-fun tostr_num ((_ FloatingPoint 11 53)) String)
(declare-fun strto_num (String) (_ FloatingPoint 11 53))
; Uninterpreted functions for math library calls.
(declare-fun math_sin ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_cos ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_tan ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_asin ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_acos ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_atan ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_sinh ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_cosh ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_tanh ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_exp ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_log ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_log10 ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))

; Uninterpreted FP power for `^`. z3 has no native FP exponent,
; so we treat pow_fp as an opaque function — both traces feed
; the same axioms, so deterministic input -> deterministic
; output even though the abstract semantics are opaque.
(declare-fun pow_fp ((_ FloatingPoint 11 53) (_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))

; ldexp(x, n) = x * 2^n. Pure FP: encode 2^n by building the
; IEEE biased exponent directly. Under-specs IEEE for n outside
; [-1022, 1023] (overflow/subnormal collapse), but both traces
; use the same definition, so equivalence holds.
(define-fun smt_ldexp ((x (_ FloatingPoint 11 53))
                      (n (_ FloatingPoint 11 53)))
                     (_ FloatingPoint 11 53)
    (fp.mul RNE x
        (fp #b0
            ((_ extract 10 0)
                (bvadd ((_ fp.to_sbv 16) RTZ n) #x03ff))
            (_ bv0 52))))

(declare-fun math_atan2 ((_ FloatingPoint 11 53) (_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))

; Uninterpreted functions for FFI external C calls (CALLXS).
; Indexed by arity. Both unopt and opt traces apply the same
; function to congruent arguments, so equivalent FFI calls
; match by congruence even though we have no semantic model
; of the underlying C routine.
(declare-fun callxs_1 ((_ BitVec 64)) (_ BitVec 64))
(declare-fun callxs_2 ((_ BitVec 64) (_ BitVec 64)) (_ BitVec 64))
(declare-fun callxs_3 ((_ BitVec 64) (_ BitVec 64) (_ BitVec 64)) (_ BitVec 64))
(declare-fun callxs_4 ((_ BitVec 64) (_ BitVec 64) (_ BitVec 64) (_ BitVec 64)) (_ BitVec 64))

; `(fp2bv64 x)` is the IEEE-754 encoding of the double x -- the
; bytes an FFI store writes. Declared, not defined: float -> bitvector
; is not a function for NaN, so SMT-LIB has no operator for it
; (https://github.com/cvc5/cvc5/discussions/9277). Each use ties
; the result down through the standard reverse direction, which
; determines it for everything but NaN:
;
;   (assert (= x ((_ to_fp 11 53) (fp2bv64 x))))
;
; A function, not a fresh constant per store, so both traces get
; the same values by congruence.
(declare-fun fp2bv64 ((_ FloatingPoint 11 53)) (_ BitVec 64))

; String reverse for lj_buf_putstr_reverse. Uninterpreted, like
; the math_* / pow_fp / callxs_* helpers above: both traces apply
; the same function to congruent arguments, so equivalent traces
; match by congruence even with no semantic model. A constant
; argument never reaches this -- ir/CALLL.lua reverses it in Lua
; and emits the resulting literal.
(declare-fun str_reverse (String) String)
]]):format(MAXSNAP, MAXSNAP, MAXSNAP, MAXSNAP, MAXSNAP)
-- luacheck: pop

-- We need to prefix field table access
-- names (`tab.hmask`, `tab.asize`)
-- with some string, to reduce probability
-- of interfering with user keys.
local FIELD_TAB_PREFIX = '```'

-- String buffer slot.
local STRING_BUFF_SLOT = FIELD_TAB_PREFIX .. 'bufhdr'

return {
    LJOPT_SMTLIB = LJOPT_SMTLIB,
    MAXSNAP = MAXSNAP,
    FIELD_TAB_PREFIX = FIELD_TAB_PREFIX,
    STRING_BUFF_SLOT = STRING_BUFF_SLOT,
}
