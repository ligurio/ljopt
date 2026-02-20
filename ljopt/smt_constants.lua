-- Unfortunately I couldn't find a way yet to implement
-- trace exits for arbitrary length.
local MAXSNAP = 500

-- This variable contains SMT library helpers to be used
-- by ljopt.
--
-- zero_pointer_i_1d - 1D array of zeros. Used in initialization.
local LJOPT_SMTLIB = ([[
(define-fun lsb ((x (_ BitVec %d))) (_ BitVec %d) (ite (not (= x (_ bv0 %d))) (_ bv1 %d) (_ bv0 %d)))
(define-const zero_pointer (Array Int (_ BitVec 64))
  ((as const (Array Int (_ BitVec 64))) #x0000000000000000))
(define-const zero_pointer_i_1d (Array Int Int)
  ((as const (Array Int Int)) 0))
]]):format(MAXSNAP, MAXSNAP, MAXSNAP, MAXSNAP, MAXSNAP)

return {
    LJOPT_SMTLIB = LJOPT_SMTLIB,
    MAXSNAP = MAXSNAP,
}
