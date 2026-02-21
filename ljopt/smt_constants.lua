-- Unfortunately I couldn't find a way yet to implement
-- trace exits for arbitrary length.
local MAXSNAP = 500

-- This variable contains SMT library helpers to be used
-- by ljopt.
-- luacheck: push no max_line_length
local LJOPT_SMTLIB = ([[
(define-fun lsb ((x (_ BitVec %d))) (_ BitVec %d) (ite (not (= x (_ bv0 %d))) (_ bv1 %d) (_ bv0 %d)))
]]):format(MAXSNAP, MAXSNAP, MAXSNAP, MAXSNAP, MAXSNAP)
-- luacheck: pop

return {
    LJOPT_SMTLIB = LJOPT_SMTLIB,
    MAXSNAP = MAXSNAP,
}
