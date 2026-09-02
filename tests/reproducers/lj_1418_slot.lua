-- Incorrect narrowing of unary minus for number 0 in DUALNUM mode
-- (LuaJIT#1418), the non-const-on-slot variant.
-- See: https://github.com/LuaJIT/LuaJIT/issues/1418
-- See also: https://github.com/tarantool/luajit/commit/707c12bf00dafdfd3899b1a6c36435dbbf6c7022

local tostring = tostring

local function test_f(a)
  local zero = a % 1
  local mzero = -zero
  local res = tostring(mzero)
  return res
end

test_f(1)
test_f(1)
test_f(1)
assert(test_f(1) == "-0", "assertion is violated")
