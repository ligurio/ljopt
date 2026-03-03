-- Test file to demonstrate LuaJIT incorrect optimizations across
-- the `table.clear()` call: HREF is forwarded from a table created
-- with TNEW.
-- See also: https://github.com/LuaJIT/LuaJIT/issues/792.

local table_clear = require('table.clear')

local NITERATIONS = 4
local MAGIC = 42

local function test_href_fwd_tnew(tab_number)
  local field_value_after_clear
  for _ = 1, NITERATIONS do
    -- Create a table on trace to make the optimization work.
    local tab = {}
    -- Use an additional table to alias the created table with the
    -- `8` key.
    local tab_array = {tab, {0}}
    -- HREF to be forwarded. Use 8 to be in the hash part.
    tab[8] = MAGIC
    table_clear(tab_array[tab_number])
    -- It should be `nil`, since table is cleared.
    field_value_after_clear = tab[8]
  end
  return field_value_after_clear
end

-- First, compile the trace that clears the not-interesting table.
test_href_fwd_tnew(2)
-- Now run the trace and clear the table, from which we take HREF.
assert(test_href_fwd_tnew(1) == nil, 'HREF forward from TNEW')
