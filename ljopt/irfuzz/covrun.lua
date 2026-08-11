-- Coverage driver: runs one fuzzer mode through the FOLD engine
-- and skips the solver, so a gcov-instrumented LuaJIT shows which
-- optimizer paths the generator actually reaches.
--
--   luajit ljopt/irfuzz/covrun.lua <mode> [limit]
--
-- One mode per process: gcov merges counters across runs, so a
-- crash in one mode keeps the coverage of the others.
--
-- The `recorded` mode is the exception to everything above: it
-- compiles real Lua with the real JIT instead of replaying a
-- synthetic stream, because the recorder-driven half of the
-- optimizer has no other caller. It needs the JIT left on.
if os.getenv("COV_JITOFF") and arg[1] ~= "recorded" then jit.off() end

local check = require("ljopt.irfuzz.check")
local enum = require("ljopt.irfuzz.enum")
local gen = require("ljopt.irfuzz.gen")

local IRT = { int = gen.IRT_INT, num = gen.IRT_NUM, i64 = gen.IRT_I64 }

local mode = arg[1] or error("usage: covrun.lua <mode> [limit]")
local limit = tonumber(arg[2]) or 1e9
local skip = tonumber(arg[3]) or 0
local loop = os.getenv("COV_LOOP") ~= nil

local function drive_seeds(opts)
    local ok, skipped = 0, 0
    for seed = 1, limit do
        opts.loop = loop
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
            local r = check.build_from(tr.insns, tr.outputs, { loop = loop })
            if r.skipped then skipped = skipped + 1 else ok = ok + 1 end
            local step = skip > 0 and 1 or 5000
            if n % step == 0 then io.stderr:write(("  %d\n"):format(n)) end
        end
        if n >= limit then break end
    end
    return ok, skipped
end

-- Compile every chunk in recorded.lua at -O3 and count the traces
-- it produced. Hot thresholds are lowered so a 200-iteration loop
-- is enough, and each chunk runs in a pcall: a chunk that cannot
-- run on this build (no FFI, say) must not take the run down.
-- Each optimization is also switched off once on its own. A
-- disabled pass is not dead weight for coverage: several rules
-- have a "this optimization is off" arm that no -O3 run can
-- reach, and turning one pass off changes what the others are
-- handed.
local RECORDED_OPTS = {
    "", "-abc", "-fold", "-cse", "-dse", "-fwd", "-narrow",
    "-loop", "-sink", "-fuse",
}

local function drive_recorded()
    local recorded = require("ljopt.irfuzz.recorded")
    local ok, failed = 0, 0
    jit.on()
    for _, flag in ipairs(RECORDED_OPTS) do
        jit.opt.start(3, "hotloop=3", "hotexit=3", "tryside=3")
        if flag ~= "" then jit.opt.start(flag) end
        local nok, nerr = 0, 0
        for _, chunk in ipairs(recorded.chunks) do
            jit.flush()
            local fn = assert(load(chunk.code, chunk.name))
            if pcall(fn) then nok = nok + 1 else nerr = nerr + 1 end
        end
        ok, failed = ok + nok, failed + nerr
        io.stderr:write(("  %-8s %3d ok %3d err\n"):format(
            flag == "" and "-O3" or flag, nok, nerr))
    end
    jit.flush()
    return ok, failed
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
    narrow = function() return drive_iter(enum.iter_narrow) end,
    sink = function() return drive_iter(enum.iter_sink) end,
    buffers = function() return drive_iter(enum.iter_buffers) end,
    abc = function() return drive_iter(enum.iter_abc) end,
    upval = function() return drive_iter(enum.iter_upval) end,
    ahref = function() return drive_iter(enum.iter_ahref) end,
    strops = function() return drive_iter(enum.iter_strops) end,
    bufcalls = function() return drive_iter(enum.iter_bufcalls) end,
    shapes = function() return drive_iter(enum.iter_shapes) end,
    xref = function() return drive_iter(enum.iter_xref) end,
    recorded = function() return drive_recorded() end,
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
