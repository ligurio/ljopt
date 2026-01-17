local is_coverage_enabled = os.getenv("LJOPT_COVERAGE")
local is_debug_enabled = os.getenv("LJOPT_DEBUG")
local is_strict_mode_enabled = os.getenv("LJOPT_STRICT")

local function is_debug_mode()
    return is_debug_enabled
end

local function set_debug_mode(val)
    is_debug_enabled = val
end

local function is_strict_mode()
    return is_strict_mode_enabled
end

local function set_strict_mode(val)
    is_strict_mode_enabled = val
end

local function is_coverage_mode()
    return is_coverage_enabled
end

local function set_coverage_mode(val)
    is_coverage_enabled = val
end

return {
    is_debug_mode = is_debug_mode,
    set_debug_mode = set_debug_mode,
    is_strict_mode = is_strict_mode,
    set_strict_mode = set_strict_mode,
    is_coverage_mode = is_coverage_mode,
    set_coverage_mode = set_coverage_mode,
}
