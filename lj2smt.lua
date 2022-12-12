local bcread = require("bcread")

print("Read", arg[1])
local ok, fd = pcall(io.open, arg[1], "r")
if ok == false or type(fd) ~= "userdata" then
    fd = io.stdout
end

local bc = fd:read("*all")
print(bcread.dump(bc))
