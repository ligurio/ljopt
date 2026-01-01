local ffi = require("ffi")
local vla_t = ffi.typeof("uint8_t[?]")

local t = {}
for _ = 0, 255 do
  table.insert(t, vla_t(1))
end
