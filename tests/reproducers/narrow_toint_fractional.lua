-- (int)(x + k) vs (int)x + k under lj_opt_narrow's IRCONV_ANY path.
-- string.sub's start argument goes through lj_opt_narrow_toint,
-- which emits CONV int num ANY -- a narrowable sink. `y` comes out
-- of a table so it stays a real SLOAD num, not a folded constant.
local s = "abcdef"
local ys = {}
for i = 1, 400 do ys[i] = -0.5 end

local function f(y) return s:sub(y + 3) end

local out = {}
for i = 1, 400 do out[i] = f(ys[i]) end

local first, last = out[1], out[400]
print("cold (interpreted):", first)
print("hot  (jitted)     :", last)
print(first == last and "MATCH" or "*** MISMATCH ***")
