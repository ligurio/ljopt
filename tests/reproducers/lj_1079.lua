-- TODO: Convert missed reproducers for LuaJIT #1079 to regression
-- tests, see [1].
--
-- 1. https://github.com/ligurio/ljopt/issues/42

local bit = require('bit');
local res = 0
for i = 1, 10 do
  res = tonumber(bit.rol(bit.band(i, 127LL), 32))
end
assert(res ~= 0, "folding bitwise rol")
