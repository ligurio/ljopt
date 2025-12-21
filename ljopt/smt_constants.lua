-- Unfortunately I couldn't find a way yet to implement
-- trace exits for arbitrary length.
local MAX_TRACE_EXITS = 1024

-- This variable contains SMT library helpers to be used
-- by ljopt.
local LJOPT_SMTLIB = ([[
(define-fun lsb ((x (_ BitVec %d))) (_ BitVec %d) (bvand x (bvneg x)))
]]):format(MAX_TRACE_EXITS, MAX_TRACE_EXITS)

return {
    LJOPT_SMTLIB = LJOPT_SMTLIB,
    MAX_TRACE_EXITS = MAX_TRACE_EXITS,
}
