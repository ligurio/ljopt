local function add(a, b)
	return a + b
end

local bc = string.dump(add)

local fd = io.open("example.luac", "wb")
fd:write(bc)
fd:close()
