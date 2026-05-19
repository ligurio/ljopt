local dev_checks = require("ljopt.dev_checks")

local is_coverage_enabled = os.getenv("LJOPT_COVERAGE") ~= nil
local is_debug_enabled = os.getenv("LJOPT_DEBUG") ~= nil
-- If enabled solver will print model (counterexample)
-- if formula is SAT.
local is_dump_model_enabled = os.getenv("LJOPT_DUMP_MODEL") ~= nil
local is_strict_mode_enabled = os.getenv("LJOPT_STRICT") ~= nil

-- If disabled we can miss some traces,
-- if such traceback do not have a counterpart trace
-- in second launch.
local is_strict_traces_matching_enabled =
    os.getenv("LJOPT_STRICT_TRACE_MATCHING") ~= nil

-- Drops the final equivalence-check disjunct so the emitted
-- formula is just the constraints accumulated during execution.
-- With the check removed the formula MUST be SAT1. Used to
-- validate that the per-trace constraints alone do not exclude
-- the recorded execution.
local is_verify_ljopt_correctness_enabled =
    os.getenv("VERIFY_LJOPT_CORRECTNESS") ~= nil

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

local function is_strict_traces_matching()
    return is_strict_traces_matching_enabled
end

local function set_strict_traces_matching(val)
    dev_checks("boolean")
    is_strict_traces_matching_enabled = val
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

local function is_verify_ljopt_correctness()
    return is_verify_ljopt_correctness_enabled
end

return {
    is_debug_mode = is_debug_mode,
    set_debug_mode = set_debug_mode,
    is_strict_mode = is_strict_mode,
    set_strict_mode = set_strict_mode,
    is_strict_traces_matching = is_strict_traces_matching,
    set_strict_traces_matching = set_strict_traces_matching,
    is_coverage_mode = is_coverage_mode,
    set_coverage_mode = set_coverage_mode,
    is_dump_model = is_dump_model,
    is_verify_ljopt_correctness = is_verify_ljopt_correctness,
}
