local ffi = require("ffi")

local point = ffi.typeof[[
struct { double x, y; }
]]

local v = point(1.0, 2.0)
for _ = 1, 100 do
  --[[A]] local t = {v}
  v = point(v.y, v.x)
end

assert(v.x == 1)
assert(v.y == 2)
