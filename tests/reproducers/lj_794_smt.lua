-- A variant of <lj_794.lua> that only records the trace: the
-- original crashes the buggy build before ljopt can read the
-- IR out of it, and the SMT check needs the trace, not the
-- segfault.
local arr = {1}
local function test(tab, to)
    local v = 0
    local s = 1
    for i = 1, to do
        if i > 1 then
            v = tab[1]
            v = tab[s]
            s = -1000000
        end
    end
    return v
end
test(arr, 3)
