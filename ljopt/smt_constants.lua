-- Unfortunately I couldn't find a way yet to implement
-- trace exits for arbitrary length.
local MAXSNAP = 500

-- This variable contains SMT library helpers to be used
-- by ljopt.
local LJOPT_SMTLIB = ([[
(define-fun lsb ((x (_ BitVec %d))) (_ BitVec %d) (ite (not (= x (_ bv0 %d))) (_ bv1 %d) (_ bv0 %d)))
(define-const zero_pointer (Array Int (_ BitVec 64))
  ((as const (Array Int (_ BitVec 64))) #x0000000000000000))
]]):format(MAXSNAP, MAXSNAP, MAXSNAP, MAXSNAP, MAXSNAP)

local TAB_OFFSETS = {
    meta = 0,
    array = 1,
    node = 2,
    asize = 3,
    hmask = 4,
    nomm = 5, 
    hsize = 5, -- It's our field, to maintain hmask changes.
    OFFSETS_SIZE = 6
}

return {
    LJOPT_SMTLIB = LJOPT_SMTLIB,
    MAXSNAP = MAXSNAP,
    TAB_OFFSETS = TAB_OFFSETS,
}
