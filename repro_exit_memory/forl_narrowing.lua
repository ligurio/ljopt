-- The FORL narrowing test's chunk (tests/tests.lua, unroll_n = 1).
local function foo()
    local t = {}
    for i = 1, 50 do t[i] = i end
    return t[10]
end
foo()
foo()
foo()
