-- file.lua
function add(a, b)
	return a + b
end

local function sub(a, b)
	return a - b
end

number_1 = 123
local number_2 = 100
print(add(number_1, number_2))
print(sub(number_1, number_2))
