local ffi = require("ffi")
local bit = require("bit")
local zero = ffi.new("struct { uint8_t u8; }", 0)
local v1, v2
for _ = 1, 60 do
  v1 = bit.bnot(zero.u8)
  v2 = bit.bnot(ffi.cast("int64_t", zero.u8))
end
assert(bit.bnot(v1) == 0, "assertion is violated")
assert(bit.bnot(v2) == 0LL, "assertion is violated")
