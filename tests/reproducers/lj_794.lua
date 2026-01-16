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

-- Warm the loop up
test(arr, 55)
-- Compile the loop
test(arr, 3)
-- Run the loop
print(test(arr, 3))
