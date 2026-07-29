-- Solver backend dispatcher.
--
-- Callers just `require("tests.smtlib2")` and get whichever
-- backend is selected, so adding or switching a solver touches
-- this file only. cvc5 is the default; LJOPT_SMT=z3 picks z3:
--
--   make test                 -- cvc5
--   LJOPT_SMT=z3 make test    -- z3
--
-- Returns the backend *module*, so the API stays new(), :parse(),
-- :check(), .result.
local ljopt_config = require("ljopt.config")

local solver_lib = "tests.smtlib2_" .. ljopt_config.get_smt_solver()
return require(solver_lib)
