-- Test file to demonstrate LuaJIT incorrect optimizations across
-- the `table.clear()` call: the guard on HREFK is dropped.
-- See also: https://github.com/LuaJIT/LuaJIT/issues/792.

local table_clear = require('table.clear')

local NITERATIONS = 4
local MAGIC = 42

local function test_not_dropped_guard_on_hrefk(tab_number)
  local tab, field_value_after_clear
  for _ = 1, NITERATIONS do
    -- Create a table on trace to make the optimization work.
    tab = {hrefk = MAGIC}
    -- Use an additional table to alias the created table with the
    -- `hrefk` key.
    local tab_array = {tab, {hrefk = 0}}
    table_clear(tab_array[tab_number])
    -- It should be `nil`, since it is cleared.
    -- If the guard is dropped for HREFK, the value from the TDUP
    -- table is taken instead, without the type check. This leads
    -- to incorrectly returned (swapped) values.
    field_value_after_clear = tab.hrefk
    tab.hrefk = MAGIC
  end
  return field_value_after_clear, tab.hrefk
end

-- First, compile the trace that clears the not-interesting table.
test_not_dropped_guard_on_hrefk(2)
-- Now run the trace and clear the table, from which we take
-- HREFK.
local field_value_after_clear, tab_hrefk = test_not_dropped_guard_on_hrefk(1)

assert(field_value_after_clear == nil, 'correct field value after table.clear')
assert(tab_hrefk == MAGIC, 'correct value set in the table that was cleared')
