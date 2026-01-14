local ffi = require('ffi')
local ljopt_config = require('ljopt.config')

local has_luacov, runner = pcall(require, 'luacov.runner')

-- Module with utilities for collecting code coverage from
-- external processes.
local export = {
    DEFAULT_EXCLUDE = {
        '/ljopt/ir_dump.lua/',
        '/.rocks/',
        '/test/',
    },
}

ffi.cdef[[
int chdir(const char *path);
char *getcwd(char* buf, size_t size);
]]

local C = ffi.C

-- Return the name of the current working directory.
local function cwd()
    -- Buffer for current directory.
    local buf = ffi.new('char[256]')
    local current_dir = C.getcwd(buf, 256)
    return ffi.string(current_dir)
end
export.cwd = cwd

-- Change working directory.
-- Return boolean: true if success, false if failure.
local function chdir(path)
    local result = C.chdir(path)
    -- On success, zero is returned.  On error, -1 is returned.
    return result == 0 and true or false
end

local function with_cwd(dir, fn)
    local old = cwd()
    assert(chdir(dir), 'Failed to chdir to ' .. dir)
    fn()
    assert(chdir(old), 'Failed to chdir to ' .. old)
end

local function coverage_enable()
    local root = cwd()
    -- Change directory to the original root so luacov can find
    -- default config and resolve relative filenames.
    with_cwd(root, function()
        local config = runner.load_config()
        config.exclude = config.exclude or {}
        for _, item in pairs(export.DEFAULT_EXCLUDE) do
            table.insert(config.exclude, item)
        end
        runner.init(config)
    end)
end

function export.enable()
    if ljopt_config.is_coverage_mode() then
        io.stdout:write('code coverage is enabled\n')
        if not has_luacov then
            io.stdout:write('luacov is not available\n')
        end
        coverage_enable()
    end
end

function export.shutdown()
    if runner.initialized then
        runner.shutdown()
    end
end

function export.toggle_debug_hook()
  local hook, mask, count
  return function()
    local cur_hook, cur_mask, cur_count = debug.gethook()
    if hook == nil then
      -- Save hook settings and disable debug hook.
      hook, mask, count = cur_hook, cur_mask, cur_count
      debug.sethook()
      return
    end
    -- Enable debug hook with saved settings.
    debug.sethook(hook, mask, count)
    hook, mask, count = nil, nil, nil
  end
end

return export
