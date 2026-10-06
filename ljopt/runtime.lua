local ir_dump = require('ljopt.ir_dump')
local utils = require('ljopt.utils')
local toggle_debug_hook = require('tests.coverage').toggle_debug_hook()

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

local function load_chunk(lua_code)
    local fn, err = loadstring(lua_code)
    if fn == nil then
        error(('cannot load Lua code: %s'):format(err))
    end
    return fn
end

local function record_sandboxed(chunk, opt, is_debug_mode)
    -- Disable coverage to not interfere with recorded traces.
    toggle_debug_hook()
    local fn = type(chunk) == 'string' and load_chunk(chunk) or chunk
    assert(type(fn) == 'function', 'expected Lua code or a function')
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

local function record_both(lua_code, opt1, opt2, is_debug_mode)
    local fn = load_chunk(lua_code)
    local rec1 = record_sandboxed(fn, opt1, is_debug_mode)
    utils.debug_msg(string.rep('=', 60))
    local rec2 = record_sandboxed(fn, opt2, is_debug_mode)
    return rec1, rec2
end

return {
    capture = capture,
    load_chunk = load_chunk,
    record_both = record_both,
    record_sandboxed = record_sandboxed,
}
