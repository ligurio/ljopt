-- Incorrect restore of sunk tables with double IR_NEWREF emission
-- (LuaJIT#1128).
-- See: https://github.com/LuaJIT/LuaJIT/issues/1128
-- See also: https://github.com/tarantool/luajit/commit/005e8cea3173879bb838fe48e2eb734baca23f0a

local take_side

local function trace_base(num)
  local tab = {}
  tab.key = false
  -- This check can't be folded since num can be NaN.
  tab.key = num == num
  -- The side trace emits NEWREF for "key" twice.
  if take_side then end
  return tab.key
end

local function trace_base_wp(num)
  return trace_base(num)
end
jit.off(trace_base_wp)

local function trace_2newref(num)
  local tab = {}
  tab.key1 = false
  -- This op can't be folded since num can be -0.
  tab.key1 = num + 0
  tab.key2 = false
  -- This check can't be folded since num can be NaN.
  tab.key2 = num == num
  if take_side then end
  return tab.key1, tab.key2
end

local function trace_2newref_wp(num)
  return trace_2newref(num)
end
jit.off(trace_2newref_wp)

-- Compile parent traces.
trace_base_wp(0)
trace_base_wp(0)
trace_2newref_wp(0)
trace_2newref_wp(0)

-- Compile side traces.
take_side = true
trace_base_wp(0)
trace_base_wp(0)
trace_2newref_wp(0)
trace_2newref_wp(0)

assert(trace_base(0) == true, "assertion is violated")

local r1, r2 = trace_2newref(0)
assert(r1 == 0, "assertion is violated")
assert(r2 == true, "assertion is violated")
