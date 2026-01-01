local a, b = "", ""
local c

for _ = 1, 1000 do
  c = a .. "a"
  a = "l" .. b
  b = "u"
end

assert(c == "lua", "assertion is violated")
