-- Misbehaviour on 64-bit bit.band() operands in the DUALNUM mode
-- (LuaJIT#1273).
-- See: https://github.com/LuaJIT/LuaJIT/issues/1273
-- See also: https://github.com/tarantool/luajit/commit/8cd79d198df4b0e14882a663a1673e1308f09899

local bit = require('bit')

local EXPECTED = 2 ^ 33 + 0LL
local MASK = EXPECTED

-- On the buggy build the 64-bit operand is coerced to 32 bits, so
-- the upper bits are lost.
assert(bit.band(2 ^ 33, MASK) == EXPECTED, "assertion is violated")
