-- Omission of the guarded CONV int.num in the DUALNUM mode
-- (tarantool#9145).
-- See: https://github.com/tarantool/luajit/commit/eac9ead5bfa699d2dfc663022fbeb2ab633285ef

-- Type instability in the loop-carried dependency, so the checked
-- CONV int.num is emitted.
local data = {0, 0.1, 0, 0 / 0}
local sum = 0.1

for _, val in ipairs(data) do
  if val == val then
    sum = sum + val
  end
end

-- On the buggy build the guarded CONV is eliminated, the third
-- side exit is taken and the sum becomes NaN.
assert(sum == sum, "assertion is violated")
