-- Test file to demonstrate LuaJIT misbehaviour during loop
-- unrolling and load forwarding for newly created tables.
-- See also https://github.com/LuaJIT/LuaJIT/issues/994.

-- TODO: test that compiled traces don't always exit by the type
-- guard. See also the comment for the TDUP test chunk.

-- TNEW.
local result
local stored_tab = {1}
local slot = {}
local key = 1

jit.opt.start('hotloop=1')
-- The trouble happens during loop unrolling when we copy
-- `>+ num ALOAD` IR in the context of the table on the previous
-- iteration instead of a new one created via TNEW containing no
-- values (so type nil should be used instead of num).
for _ = 1, 5 do
  local t = slot
  -- Use a non-constant key to avoid LJ_TRERR_GFAIL and undoing
  -- the loop.
  result = t[key]
  -- Swap table loaded by SLOAD to the created via TNEW.
  slot = _ % 2 ~= 0 and stored_tab or {}
end
assert(result, nil, 'TNEW load forwarding was successful')

-- TDUP.
for _ = 1, 5 do
  local t = slot
  -- Now use constant key slot to get necessary branch.
  -- LJ_TRERR_GFAIL isn't triggered here.
  -- See `fwd_ahload()` in <src/lj_opt_mem.c> for details.
  result = t[1]
  -- The constant table should contain the key with a different
  -- type.
  slot = _ % 2 ~= 0 and stored_tab or {true}
end
assert(result, true, 'TDUP load forwarding was successful')

-- TDUP, primitive types.
for i = 1, 5 do
  local t = slot
  -- Now use constant key slot to get necessary branch.
  -- LJ_TRERR_GFAIL isn't triggered here.
  -- See `fwd_ahload()` in <src/lj_opt_mem.c> for details.
  result = t[1]
  -- The constant tables should contain different booleans
  -- (primitive types).
  slot = i % 2 ~= 0 and {false} or {true}
end
assert(result, true, 'TDUP load forwarding (primitive types) was successful')
