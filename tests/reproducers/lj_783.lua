-- Test file to demonstrate LuaJIT's incorrect fold optimization
-- x - (-0) ==> x.

jit.opt.start('hotloop=1')

local function foo(a)
    return a - (-0.0)
end

foo(-0.0)
foo(-0.0)
foo(-0.0)
foo(-0.0)
foo(-0.0)
foo(-0.0)
foo(-0.0)

assert(tostring(foo(-0.0)) == '0', '-0 folding in simplify_numsub_k')
