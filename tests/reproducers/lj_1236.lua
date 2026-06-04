-- Incorrect narrowing for huge numbers (LuaJIT#1236).
-- See: https://github.com/LuaJIT/LuaJIT/issues/1236
--
-- IEEE-754 doubles can't hold integral precision for |x| >= 2^53.
-- Narrowing backpropagates an i64 conversion across ADD/SUB, so
--   (int64)((double)x + 1.0) - (int64)x
-- is rewritten to integer arithmetic that yields 1 instead of the
-- FP-accurate 0. JIT trace (narrowed) diverges from the
-- interpreter. The bug is still OPEN upstream, so ljopt reports
-- `sat` (opt-trace vs unopt-trace inequivalent) on any build.

local s = 2^53
local v = {}
for i = 1, 100 do
  v[i] = s + 1 - 0LL - s
end

-- Interpreter computes 0LL; the narrowed JIT trace stores 1LL.
assert(tonumber(v[100]) == 0,
    "incorrect narrowing for huge numbers: plain loop")
