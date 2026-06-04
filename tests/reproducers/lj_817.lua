-- pow() optimization inconsistency (LuaJIT#684, LuaJIT#817).
-- See: https://github.com/LuaJIT/LuaJIT/issues/817
--
-- On the buggy LuaJIT the FOLD rule `2.0 ^ i ==> ldexp(1.0, i)`
-- rewrites the optimised trace, while the interpreter (and the
-- unoptimised trace) compute pow(2.0, i). These are not
-- interchangeable -- the result depends on the libm
-- implementation -- so the optimised trace diverges from the
-- unoptimised one.
--
-- (The sibling fold `x ^ 0.5 ==> sqrt(x)` is the same bug class
-- but lowers to fp.sqrt, which the in-process z3 solver leaves
-- `unknown`; the 2^i case lowers to ldexp and stays decidable.)
--
-- The fix (tarantool/luajit 203a9868, upstream 9512d5c1) drops the
-- fold, after which both traces keep POW and ljopt proves them
-- equivalent (unsat).

jit.opt.start('hotloop=1')

local function f()
  local v = {}
  for i = 1, 100 do
    v[i] = 2 ^ i
  end
  return v
end

f()
