local is_debug_var = os.getenv("LJOPT_DEBUG")
local is_coverage_var = os.getenv('LJOPT_COVERAGE')
local is_strict_mode_var = os.getenv("LJOPT_STRICT")

local function is_debug()
    return is_debug_var
end

local function set_debug(val)
    is_debug_var = val
end

local function is_strict_mode()
    return is_strict_mode_var
end

local function set_strict_mode(val)
    is_strict_mode_var = val
end

local function is_coverage()
    return is_coverage_var
end

local function set_coverage(val)
    is_coverage_var = val
end

return {
    is_debug = is_debug,
    set_debug = set_debug,
    is_strict_mode = is_strict_mode,
    set_strict_mode = set_strict_mode,
    is_coverage = is_coverage,
    set_coverage = set_coverage,
}
