-- Test file to demonstrate LuaJIT incorrect optimizations across
-- the `table.clear()` call: AREF is forwarded from a table created
-- with TDUP.
-- See also: https://github.com/LuaJIT/LuaJIT/issues/792.

local table_clear = require('table.clear')

local NITERATIONS = 4
local MAGIC = 42

local function test_aref_fwd_tdup(tab_number)
  local field_value_after_clear
  for _ = 1, NITERATIONS do
    -- Create a table on trace to make the optimization work.
    local tab = {nil}
    -- Use an additional table to alias the created table with the
    -- `1` key.
    local tab_array = {tab, {0}}
    -- AREF to be forwarded.
    tab[1] = MAGIC
    table_clear(tab_array[tab_number])
    -- It should be `nil`, since table is cleared.
    field_value_after_clear = tab[1]
  end
  return field_value_after_clear
end

-- First, compile the trace that clears the not-interesting table.
test_aref_fwd_tdup(2)
-- Now run the trace and clear the table, from which we take AREF.
assert(test_aref_fwd_tdup(1) == nil, 'AREF forward from TDUP')
