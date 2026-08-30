-- FOLD rewrites `x ^ 2` into `x * x` (lj_opt_fold.c,
-- simplify_numpow_k). The interpreter evaluates the same expression
-- with pow(), and the two do not agree: for x = 3.50000000025 the
-- exact square is 12.25000000175000014..., which rounds to
-- 12.250000001750001 (what x*x gives) while pow() returns
-- 12.25000000175. So the JIT is the accurate one, but a program
-- changes its result depending on whether the trace was compiled.
--
-- Same class as LuaJIT#817, still present on the current build.
local x = 3.50000000025
local function sq(v) return v ^ 2 end
local interp = sq(x)
local jit_res
for _ = 1, 400 do jit_res = sq(x) end

assert(interp == jit_res,
    "x^2 fold disagrees with pow(): " ..
    string.format("%.17g vs %.17g", interp, jit_res))
