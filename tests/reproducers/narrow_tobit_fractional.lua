-- lj_opt_narrow moves an unguarded num->int conversion inside an ADD:
-- bit.tobit(z + 1) is compiled as bit.tobit(z) + 1.
--
-- Both the interpreter (lj_num2bit) and the trace (IR TOBIT) round with
-- the same 2^52 bias trick, so the mismatch is not a rounding-mode
-- difference -- it is the reassociation. Rounding 0.5 first gives 0,
-- rounding 1.5 gives 2.
--
-- `z` comes out of a table so it stays a real SLOAD num; a literal is
-- constant-folded before narrowing ever runs.
local zs = {}
for i = 1, 400 do zs[i] = 0.5 end

local function g(z) return bit.tobit(z + 1) end

local out = {}
for i = 1, 400 do out[i] = g(zs[i]) end

local first, last = out[1], out[400]
print("cold (interpreted):", first)   -- 2
print("hot  (jitted)     :", last)    -- 1
print(first == last and "MATCH" or "*** MISMATCH ***")
