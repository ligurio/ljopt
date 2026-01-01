----- luafun.lua ---------------------------------------------------------------

local iterator_mt = {
  -- usually called by for-in loop
  __call = function(self, param, state) return self.gen(param, state) end,
}

local wrap = function(gen, param, state)
  return setmetatable({
    gen = gen,
    param = param,
    state = state
  }, iterator_mt), param, state
end

-- call each other
local chain_gen_r1, chain_gen_r2

chain_gen_r2 = function(param, state, state_x, ...)
  if state_x ~= nil then return { state[1], state_x }, ...  end
  local i = state[1] + 1
  if param[3 * i - 1] == nil then return nil end
  return chain_gen_r1(param, { i, param[3 * i] })
end

chain_gen_r1 = function(param, state)
  local i, state_x = state[1], state[2]
  local gen_x, param_x = param[3 * i - 2], param[3 * i - 1]
  return chain_gen_r2(param, state, gen_x(param_x, state_x))
end

local chain = function(...)
  local param = { }
  for i = 1, select('#', ...) do
    param[3 * i - 2], param[3 * i - 1], param[3 * i] -- gen, param, state
      = wrap(ipairs(select(i, ...)))
  end
  return wrap(chain_gen_r1, param, { 1, param[3] })
end

----- repro --------------------------------------------------------------------

-- local sink = arg[1] and '-sink' or '+sink'
-- print(('%s %s %s'):format(('-'):rep(8), sink, ('-'):rep(60)))

-- require('jit.dump').start('+tbisrmXaT', ('4252%s.dump'):format(sink))

-- jit.opt.start(3, 'hotloop=3', sink)

xpcall(function()
  for _ = 1, 3 do
    local gen_x, param_x, state_x = chain({ 'a', 'b', 'c' }, { 'q', 'w', 'e' })
    local tab = {}
    while true do
      local val
      state_x, val = gen_x(param_x, state_x)
      if state_x == nil then break end
      table.insert(tab, val)
    end
    -- XXX: print(unpack(tab))
  end
end, function(err)
  -- XXX: print(debug.traceback(tostring(err)))
  os.exit(1)
end)
