jit.opt.start("hotloop=1")
local value = "____________________abc____________________"
for i = 1, 20 do
  value = string.sub(value, 2, -2)
  local pos_b = string.find(value, "b", 2, true)
  assert(pos_b == (22 - i), "FAIL: position of 'b' is " .. pos_b)
end

print("OK")
