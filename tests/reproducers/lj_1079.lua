-- TODO: Convert missed reproducers for LuaJIT #1079 to regression
-- tests, see [1].
--
-- 1. https://github.com/ligurio/ljopt/issues/42

local bit = require('bit');
for i = 1, 10 do
  assert(tonumber(bit.rol(bit.band(i, 127LL), 32)) ~= 0,
    'folding bitwise rol')
end
