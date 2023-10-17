local code = [[
-- TNEW.
-- local result
local stored_tab = {1}
local slot = {}

jit.opt.start('hotloop=1')

-- TDUP.
for _ = 1, 3 do
  local t = slot
  local result = t[1]
  slot = _ % 2 ~= 0 and stored_tab or {true}
end
]]

local dump = require("jit.dump")
local name = "dump.txt"
dump.on(name)
loadstring(code)()
dump.off()
