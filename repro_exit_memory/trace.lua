-- Two stores to the same cell with a guard between them.
-- The second overwrites the first, so FINAL memory is the same
-- either way -- but at an exit taken between them the observable
-- value differs.
local function foo(t, k, i)
  t[1] = k          -- store A
  local v = t[i]    -- ABC / bounds guard on i
  t[1] = v + 1      -- store B, overwrites A
  return t[1]
end
local function driver(t)
  for j = 1, 400 do foo(t, j, 2) end
end
jit.off(driver)
local t = {0, 0, 0}
driver(t)
return t[1]
