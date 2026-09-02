local function foo(t, k, i)
  t[1] = k          -- store A
  local v = t[i]    -- guards: bounds / type
  t[1] = v + 1      -- store B (overwrites A)
  return t[1]
end
local function driver(t)
  for j = 1, 400 do foo(t, j, 2) end
end
jit.off(driver)
local t = {0, 0, 0}
driver(t)                       -- make foo's trace hot
t[1] = -1                       -- known marker
pcall(foo, t, 12345, 99)        -- i out of bounds -> exit between the stores
print("t[1] after the aborted call:", t[1])
print("expected 12345 (store A ran before the exit)")
