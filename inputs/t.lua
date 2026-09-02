
local arr_i64 = ffi.new('int64_t  [2]')
local arr_u64 = ffi.new('uint64_t [2]')
local arr_u32 = ffi.new('uint32_t [2]')

jit.opt.start('hotloop=1')

for _ = 1, 4 do
  -- Test conversion to type (at store). Also, check the
  -- conversion from number to int64_t at C array indexing.
  arr_i64[1.1] = 1.1
  arr_u64[1.1] = 1.1
  arr_u32[1.1] = 1.1
end

