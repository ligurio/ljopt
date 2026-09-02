local ffi = require('ffi')
ffi.cdef[[
typedef struct { int32_t x; double y; } P;
typedef struct { int32_t n; uint8_t b[4]; } Q;
typedef struct { int32_t v; } V;
]]
local i32 = ffi.new('int32_t[8]')
local dd  = ffi.new('double[8]')
local p = ffi.new('P')
local q = ffi.new('Q')
ffi.metatype('V', {__index = {
  bump = function(s, d) s.v = 1 % 1000003 end }})
local v = ffi.new('V')
local a, b, c, n = 1, 2, 3, 0
for i = 1, 300 do
  if (i) < (1) then
    if (a) < 1 then
    end
    if 1 < (a) then
    end
  end
  a = bit.band(a, 255)
  if 1 < 1 then
  end
  if ((tonumber(dd[((a) % 8)]))) < 1 then
    p.x = 1
  end
  if ((tonumber(i32[1]))) < 1 then
  end
  if ((219)) < (((tonumber(p.x) * 31 + 1) % 1000003)) then
    v:bump(6)
  else
    p.x = ((1 * 31 + bit.band(133, 255)) % 1000003)
  end
end
local acc = n
for k = 0, 7 do
end
acc = (acc * 31 + tonumber(p.x) + tonumber(q.n) + tonumber(v.v)) % 1000003
print(acc, a, b, c, n, tonumber1, tonumber1)