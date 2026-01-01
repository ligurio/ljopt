local NSAMPLES = 4
local NTEST = NSAMPLES * 2 - 1

local ffi = require('ffi')
local samples = ffi.new('int [?]', NSAMPLES)

-- Prepare data.
for i = 0, NSAMPLES - 1 do samples[i] = i end

local expected = {3, 2, 1, 0, 3, 2, 1}

local START = 3
local STOP = -START

local results = {}
jit.opt.start('hotloop=1')
for i = START, STOP, -1 do
  -- While recording cdata indexing the fold CONV SEXT
  -- optimization eliminate sign extension for the corresponding
  -- non constant value (i.e. stack slot). As a result the read
  -- out of bounds was occurring.
  results[#results + 1] = samples[i % NSAMPLES]
end

for i = 1, NTEST do
  assert(results[i] == expected[i], 'correct cdata indexing')
end
