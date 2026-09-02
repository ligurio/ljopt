-- Incorrect narrowing of unary minus for number 0 in DUALNUM mode
-- (LuaJIT#1418), the non-const-value variant.
-- See: https://github.com/LuaJIT/LuaJIT/issues/1418
-- See also: https://github.com/tarantool/luajit/commit/707c12bf00dafdfd3899b1a6c36435dbbf6c7022

local tostring = tostring

local function test_f(a, b)
  local mb_zero = a % b
  local mb_mzero = -mb_zero
  local res = tostring(mb_mzero)
  return res
end

test_f(2, 3)
test_f(2, 3)
assert(test_f(2, 1) == "-0", "assertion is violated")
