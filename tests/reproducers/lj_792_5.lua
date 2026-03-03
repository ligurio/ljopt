-- Test file to demonstrate LuaJIT incorrect optimizations across
-- the `table.clear()` call: the HREFK field value is incorrectly
-- forwarded from a NEWREF.
-- See also: https://github.com/LuaJIT/LuaJIT/issues/792.

local table_clear = require('table.clear')

local NITERATIONS = 4
local MAGIC = 42

local function test_not_forwarded_hrefk_val_from_newref(tab_number)
  local field_value_after_clear
  for _ = 1, NITERATIONS do
    -- Create a table on trace to make the optimization work.
    local tab = {}
    -- NEWREF to be forwarded.
    tab.hrefk = MAGIC
    -- Use an additional table to alias the created table with the
    -- `hrefk` key.
    local tab_array = {tab, {hrefk = 0}}
    table_clear(tab_array[tab_number])
    -- It should be `nil`, since it is cleared.
    field_value_after_clear = tab.hrefk
  end
  return field_value_after_clear
end

-- First, compile the trace that clears the not-interesting table.
test_not_forwarded_hrefk_val_from_newref(2)
-- Now run the trace and clear the table, from which we take
-- HREFK.
local value_from_cleared_tab = test_not_forwarded_hrefk_val_from_newref(1)

assert(value_from_cleared_tab == nil,
       'not forward the field value across table.clear')
