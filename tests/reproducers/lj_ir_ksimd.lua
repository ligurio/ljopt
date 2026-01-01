local ffi = require('ffi')

ffi.cdef[[
  typedef struct range { double start, stop, step; } range;
]]

local range = ffi.typeof('range')
local a = 1
for i = 1, 100 do
  r = range(0, -1, -a)
  -- XXX: print(i, a, r.start, r.step, r.start + r.step * 1)
  assert(a == 1)
  assert(r.start == 0)
  assert(r.step == -1)
  assert(r.start + r.step * 1 == -1)
end
