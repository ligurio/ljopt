local b = require"string.buffer"

-- jit.off()

local a = "1"
local t
local w = 1

for _ = 1, 100 do
  a = a .. "x"
  t = b.encode(w)
  a = a .. "y"
end

print(a, t)
