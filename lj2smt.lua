local bcread = require("bcread")
-- local json = require("json")

print(arg[1])
local ok, fd = pcall(io.open, arg[1], "w")
if ok == false or type(fd) ~= "userdata" then
    fd = io.stdout
end

if fd then
	local bc = fd:read("*a")
	print(bc)
	-- print(json.encode(bcread.dump(bc)))
end
