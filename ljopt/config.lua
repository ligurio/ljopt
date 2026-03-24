local dev_checks = require("ljopt.dev_checks")

local is_coverage_enabled = os.getenv("LJOPT_COVERAGE") ~= nil
local is_debug_enabled = os.getenv("LJOPT_DEBUG") ~= nil
-- If enabled solver will print model (counterexample)
-- if formula is SAT.
local is_dump_model_enabled = os.getenv("LJOPT_DUMP_MODEL") ~= nil
local is_strict_mode_enabled = os.getenv("LJOPT_STRICT") ~= nil
local loop_unroll_n = tonumber(os.getenv("LJOPT_LOOP_UNROLL_N")) or 4

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

-- When disabled, narrowing-related logic is skipped end-to-end:
local is_narrowing_enabled = os.getenv("LJOPT_DISABLE_NARROWING") == nil

local smt_solver = os.getenv("LJOPT_SMT") or "cvc5"
local solver_timeout_sec = tonumber(os.getenv("LJOPT_SMT_TIMEOUT")) or 120

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

local function is_narrowing()
    return is_narrowing_enabled
end

local function set_narrowing(val)
    dev_checks("boolean")
    is_narrowing_enabled = val
end

local function get_smt_solver()
    return smt_solver
end

local function get_solver_timeout()
    return solver_timeout_sec
end


local function get_solver_timeout_ms()
    return tostring(math.floor(get_solver_timeout() * 1000))
end

local function get_loop_unroll_count()
    return loop_unroll_n
end

return {
    get_smt_solver = get_smt_solver,
    get_solver_timeout_ms = get_solver_timeout_ms,
    get_loop_unroll_count = get_loop_unroll_count,
    is_debug_mode = is_debug_mode,
    set_debug_mode = set_debug_mode,
    is_narrowing = is_narrowing,
    set_narrowing = set_narrowing,
    is_strict_mode = is_strict_mode,
    set_strict_mode = set_strict_mode,
    is_strict_traces_matching = is_strict_traces_matching,
    set_strict_traces_matching = set_strict_traces_matching,
    is_coverage_mode = is_coverage_mode,
    set_coverage_mode = set_coverage_mode,
    is_dump_model = is_dump_model,
    is_verify_ljopt_correctness = is_verify_ljopt_correctness,
}
