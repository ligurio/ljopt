-- LuaJIT miscompile at DEFAULT -O3.
--
-- `bit.band(t.ka, ...)` reads a stale value of t.ka: the store
-- `t.ka = i` from earlier iterations is not observed by the read in
-- the compiled inner loop.
--
-- At the end of outer iteration i, t.ka == i, so s must be i.
-- Expected final s == 400.
--
--   luajit -joff -> 400   correct
--   luajit -O2   -> 400   correct
--   luajit -O3   -> 100   WRONG
--
-- Any bit.* operation on the loaded field triggers it (band, bor,
-- tobit -- they all lower to IR TOBIT). A plain read, or math.floor,
-- does not.
local t = {ka = 0}
local s = 0
for i = 1, 400 do
  for j = 1, 5 do
    s = bit.band(t.ka, 65535)
    t.ka = i
  end
end
print(s)
assert(s == 400, "stale table read: s = " .. tostring(s))
