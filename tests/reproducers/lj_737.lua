-- Use-def snapshot analysis does not consider slots used by open
-- upvalues (LuaJIT#737).
-- See: https://github.com/LuaJIT/LuaJIT/issues/737
-- See also: https://github.com/tarantool/luajit/commit/ca0de768be31f10ccd35569f786a960a76e9fdbb

local fmod = math.fmod

local EXPECTED = 'expected'

local function wrapped_trace(create_closure)
  local local_upvalue, closure
  if create_closure then
    closure = function() return local_upvalue end
  end
  for i = 1, 4 do
    if i == 2 then
      -- On the buggy build this slot is considered unused by the
      -- use-def analysis (no open upvalue on the first call), so
      -- the restored closure returns nil instead of EXPECTED.
      local_upvalue = EXPECTED
      -- Emit an additional snapshot after setting the upvalue.
      if i == 0 then end
      -- Stitching ends the trace here.
      fmod(1, 1)
      return closure
    end
  end
end

local func_with_uv = wrapped_trace(false)
assert(func_with_uv == nil, "assertion is violated")

func_with_uv = wrapped_trace(true)
assert(type(func_with_uv) == 'function', "assertion is violated")
assert(func_with_uv() == EXPECTED, "assertion is violated")
