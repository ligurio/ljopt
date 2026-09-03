local ir_dump = require('ljopt.ir_dump')
-- tests.coverage is a test-only module; when it is not installed
-- (e.g. a luarocks install without the test suite) toggling the
-- debug hook must be a no-op.
local has_coverage, coverage = pcall(require, 'tests.coverage')
local toggle_debug_hook = has_coverage
    and coverage.toggle_debug_hook()
    or function() end

-- Disable print to avoid stdout modifications.
local function capture(f, ...)
    local result = {}
    local old = print
    _G.print = function(...)
        local args = {...}
        for i = 1, select('#', ...) do
            args[i] = tostring(args[i])
        end
        table.insert(result, table.concat(args, '\t'))
    end
    local ok, res = pcall(f, ...)
    _G.print = old
    return ok, res, table.concat(result, '\n')
end

local function record_sandboxed(lua_code, opt, is_debug_mode, chunkname)
    -- Disable coverage to not interfere with recorded traces.
    toggle_debug_hook()
    local fn, err
    if chunkname ~= nil then
        fn, err = loadstring(lua_code, chunkname)
    else
        fn, err = loadstring(lua_code)
    end
    if fn == nil then
        error(('cannot load Lua code: %s'):format(err))
    end

    local env = setmetatable({}, {__index = _G})
    local mt = getmetatable('string')
    setfenv(fn, env)
    local _, res = capture(ir_dump.record, fn, opt, is_debug_mode)
    -- Recover string metatable.
    debug.setmetatable('', mt)
    -- Enable coverage.
    toggle_debug_hook()
    return res
end

return {
    capture = capture,
    record_sandboxed = record_sandboxed,
}
