-- LuaJIT miscompile: `y = #t2 * 1` inside a loop yields the value of
-- an unrelated variable `n` once the trace is compiled.
--
-- Requires -O-dce (DCE disabled). All default levels are correct.
--
--   luajit -joff    -> 400                      (correct)
--   luajit -O3      -> 400                      (correct)
--   luajit -O3,-dce -> 1.513037037941548e+118   (WRONG)
--
-- t2 is empty, so #t2 == 0 and y must be 0 on every iteration.
-- Instead, from the iteration where the trace is installed, y takes
-- on the previous value of n. `n = n + x + y` then becomes
-- n = n + 1 + n = 2n + 1, so n doubles every iteration and ends at
-- roughly 2^391 instead of 400.
local t2 = {}
local x, y, n = 1, 2, 0
for i = 1, 400 do
  for j = 1, 5 do
    y = #t2 * 1
    local s2 = { 0, 0 }
    n = n + s2[1] - s2[2]
  end
  n = n + x + y
end
print(string.format("%.17g", n))
assert(n == 400, "miscompile: n = " .. string.format("%.17g", n))
