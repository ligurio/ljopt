local function f(...)
  local t = {}
  for i = 1, 60 do
    t[i] = select(2, ...)
  end
  assert(t[1] == t[60], tostring(t[60]))
end
f(0.5, 1.5)
