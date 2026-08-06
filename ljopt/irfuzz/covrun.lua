-- Coverage driver: runs one fuzzer mode through the FOLD engine
-- and skips the solver, so a gcov-instrumented LuaJIT shows which
-- optimizer paths the generator actually reaches.
--
--   luajit ljopt/irfuzz/covrun.lua <mode> [limit]
--
-- One mode per process: gcov merges counters across runs, so a
-- crash in one mode keeps the coverage of the others.
local check = require("ljopt.irfuzz.check")
local enum = require("ljopt.irfuzz.enum")
local gen = require("ljopt.irfuzz.gen")

local IRT = { int = gen.IRT_INT, num = gen.IRT_NUM, i64 = gen.IRT_I64 }

local mode = arg[1] or error("usage: covrun.lua <mode> [limit]")
local limit = tonumber(arg[2]) or 1e9
local skip = tonumber(arg[3]) or 0

local function drive_seeds(opts)
    local ok, skipped = 0, 0
    for seed = 1, limit do
        local r = check.build(seed, opts)
        if r.skipped then skipped = skipped + 1 else ok = ok + 1 end
        if seed % 5000 == 0 then io.stderr:write(("  %d\n"):format(seed)) end
    end
    return ok, skipped
end

local function drive_iter(make_iter)
    local ok, skipped, n = 0, 0, 0
    for tr in make_iter() do
        n = n + 1
        if n > skip then
            local r = check.build_from(tr.insns, tr.outputs, {})
            if r.skipped then skipped = skipped + 1 else ok = ok + 1 end
            local step = skip > 0 and 1 or 5000
            if n % step == 0 then io.stderr:write(("  %d\n"):format(n)) end
        end
        if n >= limit then break end
    end
    return ok, skipped
end

local function chain(t, d)
    return function()
        return enum.iter({ type = IRT[t], depth = d, ninputs = 1 })
    end
end

local MODES = {
    random = function() return drive_seeds({}) end,
    tables = function() return drive_seeds({ tables = true }) end,
    gaps = function() return drive_seeds({ include_gaps = true }) end,
    mixed = function()
        return drive_iter(function()
            return enum.iter_mixed({ depth = 2 })
        end)
    end,
    alias = function() return drive_iter(enum.iter_alias) end,
    strings = function() return drive_iter(enum.iter_strings) end,
    xmem = function() return drive_iter(enum.iter_xmem) end,
    guard = function() return drive_iter(enum.iter_guard) end,
}
for _, t in ipairs({ "int", "num", "i64" }) do
    for d = 1, 2 do
        MODES[("%s%d"):format(t, d)] = function()
            return drive_iter(chain(t, d))
        end
    end
end

local run = MODES[mode] or error("unknown mode: " .. mode)
local ok, skipped = run()
print(("%-10s %8d built, %6d skipped"):format(mode, ok, skipped))
