-- The SMT half of the LuaJIT#1194 reproducer (see lj_1194.lua).
--
-- The runtime reproducer has to *execute* the bad trace to crash,
-- and it turns the JIT off afterwards so no other trace is
-- recorded. Neither works here: ljopt records the chunk itself,
-- once per optimisation level, and the crash would take the
-- recorder down with it. What is left is the part that makes the
-- optimizer hoist the bounds check -- a loop whose table is
-- replaced on every iteration -- with the trace only compiled,
-- never run.
local table_new = require('table.new')

local function test_func()
  local limit = 3
  -- Fixed array size, so every access fits the array part.
  local s = table_new(limit, 0)
  for i = 1, limit do
    -- Don't touch the table on the hotcount warm-up iteration.
    if i ~= 1 then
      s[i] = nil
      -- The replacement has `asize == 0`: a bounds check hoisted
      -- out of the loop no longer covers the table the store
      -- lands in.
      s = {}
    end
  end
end

test_func()
