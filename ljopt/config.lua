local dev_checks = require("ljopt.dev_checks")

local is_coverage_enabled = os.getenv("LJOPT_COVERAGE") ~= nil
local is_debug_enabled = os.getenv("LJOPT_DEBUG") ~= nil
-- If enabled solver will print model (counterexample)
-- if formula is SAT.
local is_dump_model_enabled = os.getenv("LJOPT_DUMP_MODEL") ~= nil
local is_strict_mode_enabled = os.getenv("LJOPT_STRICT") ~= nil

local function is_debug_mode()
    return is_debug_enabled
end

local function set_debug_mode(val)
    dev_checks("boolean")
    is_debug_enabled = val
end

local function is_strict_mode()
    return is_strict_mode_enabled
end

local function set_strict_mode(val)
    dev_checks("boolean")
    is_strict_mode_enabled = val
end

local function is_coverage_mode()
    return is_coverage_enabled
end

local function set_coverage_mode(val)
    dev_checks("boolean")
    is_coverage_enabled = val
end

local function is_dump_model()
    return is_dump_model_enabled
end

return {
    is_debug_mode = is_debug_mode,
    set_debug_mode = set_debug_mode,
    is_strict_mode = is_strict_mode,
    set_strict_mode = set_strict_mode,
    is_coverage_mode = is_coverage_mode,
    set_coverage_mode = set_coverage_mode,
    is_dump_model = is_dump_model,
}
