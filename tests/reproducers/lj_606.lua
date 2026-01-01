local function cut_le_str(...)
  local args = {...}
  return
end

local time = os.clock()
local i = 0

while (i < 50000) do
  cut_le_str(1, 1, 4, 4)
  i = i + 1
end
