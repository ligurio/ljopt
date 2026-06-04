-- Incorrect narrowing for huge numbers (LuaJIT#1236), variant 2.
-- See: https://github.com/LuaJIT/LuaJIT/issues/1236
--
-- Same root cause as lj_1236.lua: narrowing backpropagates an
-- integer conversion across ADD, but doubles lose integral
-- precision for |x| >= 2^52, so the narrowed JIT trace diverges
-- from the interpreter. Still OPEN upstream.

local s = 2^52 - 1
local v = {}
local ffi = require("ffi")
for i = 1, 60 do
  ffi.cast("int64_t", s)
  v[i] = ffi.cast("int64_t", s + s + s)
end

-- The interpreter and the narrowed JIT trace must agree.
assert(v[1] == v[#v],
    "incorrect narrowing for huge numbers: ffi int64 cast loop")
