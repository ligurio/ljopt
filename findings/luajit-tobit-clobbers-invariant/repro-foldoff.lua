local t1, t3 = {}, {}
local a, b, c = 1, 2, 3
for i = 1, 400 do
  for j = 1, 4 do
    for j = 1, 2 do
      local u = (a < 64536) and t3 or t1
      u[1] = (c - ((a < b) and b or 0)) % 1000003
      if (((bit.band(a, 65535) * 31 + i) % 1000003) < c) then a = 127 end
    end
  end
  c = (c * 31 + 1) % 1000003
end
print(a, c, t1[1], t3[1])
