-- lj_opt_narrow moves an unguarded num->int conversion inside an
-- ADD: `bit.tobit(z + 1)` is compiled as `bit.tobit(z) + 1`.
--
-- narrow_conv_backprop() accepts a leaf it cannot narrow by paying
-- for one conversion (`count <= 1`), so the TOBIT sink sinks below
-- the addition. Both the interpreter (lj_num2bit) and the trace
-- (IR TOBIT) round with the same 2^52 bias trick, so this is not a
-- rounding-mode difference -- only the order changes. Rounding 0.5
-- first gives 0, rounding 1.5 gives 2.
--
-- Still OPEN upstream, so the bug is present on every build.
local z = 0.5
local expected = bit.tobit(z + 1)
local last
for _ = 1, 400 do
  last = bit.tobit(z + 1)
end

assert(last == expected,
    "narrowing across ADD rounds too early: bit.tobit")
