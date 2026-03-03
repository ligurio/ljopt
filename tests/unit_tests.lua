-- This file contains general unit tests
-- to tests correctnes of arbitrary
-- data structures we use.

local arith_utils = require("ljopt.ir.arith_utils")
local ljopt_config = require("ljopt.config")
local utils = require("ljopt.utils")

local smt = require("ljopt.smtlib2").new()
local test = require("tests.tap").test("ljopt")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

local function expect_fail(test, name, fun, ...)
    local success, _ = pcall(fun, ...)
    test:is(success, false, name)
end

-- Capture everything a function writes to io.stdout.
local function capture_stdout(fn)
    local chunks = {}
    local saved = io.stdout
    io.stdout = { -- luacheck: ignore 122
        write = function(_, s) chunks[#chunks + 1] = s end,
        flush = function() end,
    }
    local ok, err = pcall(fn)
    io.stdout = saved -- luacheck: ignore 122
    assert(ok, err)
    return table.concat(chunks)
end

-- Deterministic stand-in for a solver backend. `check` maps the
-- marker at the end of the formula to a verdict.
local SMT_RESULT = {
    UNSAT = -1,
    UNKNOWN = 0,
    SAT = 1,
}
local function mock_solver()
    return {
        result = SMT_RESULT,
        parse = function(_self, str)
            return type(str) == "string"
        end,
        check = function(_self, str)
            if str:sub(-7) == "UNKNOWN" then
                return SMT_RESULT.UNKNOWN
            elseif str:sub(-5) == "UNSAT" then
                return SMT_RESULT.UNSAT
            elseif str:sub(-3) == "SAT" then
                return SMT_RESULT.SAT
            end
            return SMT_RESULT.UNSAT
        end,
    }
end

test:plan(8)

test:test("merge_tables", function(test)
    test:plan(10)
    -- Test 1: Basic functionality with string keys
    local t1 = {a = 1, b = 2, c = 3}
    local t2 = {a = 10, b = 20, c = 30}
    local result = utils.merge_tables(t1, t2)
    test:is(result.a[1], 1, "Wrong a[1]")
    test:is(result.b[1], 2, "Wrong b[1]")
    test:is(result.c[1], 3, "Wrong c[1]")
    test:is(result.a[2], 10, "Wrong a[2]")
    test:is(result.b[2], 20, "Wrong b[2]")
    test:is(result.c[2], 30, "Wrong c[2]")


    -- Failure tests requires to be run in strict mode to
    -- trigger assertion.
    local strict_mode = ljopt_config.is_strict_mode()
    ljopt_config.set_strict_mode(true)

    -- Missing 'c'.
    expect_fail(test, "Left missing c", utils.merge_tables,
        {a = 1, b = 2},
		{a = 1, b = 2, c = 3})
    expect_fail(test, "Right missing c", utils.merge_tables,
	    {a = 1, b = 2, c = 3},
		{a = 1, b = 2})

    -- nil value.
    expect_fail(test, "Left nil", utils.merge_tables,
	    {a = nil},
		{a = 1})
    expect_fail(test, "Right nil", utils.merge_tables,
	    {a = 1},
		{a = nil})
    ljopt_config.set_strict_mode(strict_mode)
end)

test:test("Arithmetic utils tests", function(test)
    test:plan(3)
    local no_overflow = arith_utils.i32_overflow_check("#x000000007fffffff")
    local max_i32_inc = "#x0000000080000000"
    local positive_overflow = arith_utils.i32_overflow_check(max_i32_inc)
    local min_i32_dec = "#xffffffff7fffffff"
    local negative_overflow = arith_utils.i32_overflow_check(min_i32_dec)

    test:is(smt:check(("(assert %s)"):format(no_overflow)),
        smt.result.SAT, "SMT-LIB check no i32 overflow"
    )
    test:is(smt:check(("(assert %s)"):format(positive_overflow)),
        smt.result.UNSAT, "SMT-LIB check positive i32 overflow"
    )
    test:is(smt:check(("(assert %s)"):format(negative_overflow)),
        smt.result.UNSAT, "SMT-LIB check negative i32 overflow"
    )
end)

test:test("Trace exit merge snapshots", function(test)
    test:plan(4)
    local snapshots = {}
    snapshots[1] = {nins={1}}
    snapshots[3] = {nins={3}}

    local create_node = function()
        -- It will be extended later.
        return {
            get_flags = function(self)
                return {irt_guard = true}
            end,
        }
    end

    local nodes = {}
    nodes[1] = create_node()
    nodes[2] = create_node()
    nodes[3] = create_node()
    nodes[4] = create_node()

    local all_trace = {snapshots=snapshots}
    utils.enrich_snapshots_with_exits(nodes, all_trace)
    local snaps = all_trace.snapshots
    test:is(snaps[1].exits[1], 1, "1 guard matched with 1 snapshot")
    test:is(snaps[1].exits[2], 2, "2 guard matched with 1 snapshot")
    test:is(snaps[3].exits[1], 3, "3 guard matched with 3 snapshot")
    test:is(snaps[3].exits[2], 4, "4 guard matched with 3 snapshot")

end)

test:test("arith_utils conversion functions", function(test)
    test:plan(10)

    -- const_int_to_smt_bv:
    -- string.format %016X, no truncation.
    test:is(arith_utils.const_int_to_smt_bv(0),
        "#x0000000000000000", "const_int_to_smt_bv: zero")
    test:is(arith_utils.const_int_to_smt_bv(1),
        "#x0000000000000001", "const_int_to_smt_bv: one")
    test:is(arith_utils.const_int_to_smt_bv(256),
        "#x0000000000000100", "const_int_to_smt_bv: 256")
    -- string.format preserves full 64-bit value.
    test:is(arith_utils.const_int_to_smt_bv(2^32 + 1),
        "#x0000000100000001", "const_int_to_smt_bv: full 64-bit")
    test:is(arith_utils.const_int_to_smt_bv(-1),
        "#xFFFFFFFFFFFFFFFF", "const_int_to_smt_bv: -1")
    test:is(arith_utils.const_int_to_smt_bv(-256),
        "#xFFFFFFFFFFFFFF00", "const_int_to_smt_bv: -256")

    -- Ensure these conversions equivalent:
    -- 1. int -> smt_int_bv -> smt_fp.
    -- 2. fp -> smt_fp
    local smt_int = arith_utils.const_int_to_smt_bv(-2^31)
    local smt_fp = arith_utils.const_num_to_smt_fp(-2^31)
    test:is(smt:check(("(assert (= %s %s))"):format(
            smt_fp, arith_utils.smt_int_to_fp(smt_int)
        )), smt.result.SAT, "Int32 min -> FP conversion"
    )

    local smt_neg1_int = arith_utils.const_int_to_smt_bv(-1)
    local smt_neg1_fp = arith_utils.const_num_to_smt_fp(-1)
    test:is(smt:check(("(assert (= %s %s))"):format(
            smt_neg1_fp, arith_utils.smt_int_to_fp(smt_neg1_int)
        )), smt.result.SAT, "Int -1 -> FP conversion"
    )

    local smt_neg256_int = arith_utils.const_int_to_smt_bv(-256)
    local smt_neg256_fp = arith_utils.const_num_to_smt_fp(-256)
    test:is(smt:check(("(assert (= %s %s))"):format(
            smt_neg256_fp, arith_utils.smt_int_to_fp(smt_neg256_int)
        )), smt.result.SAT, "Int -256 -> FP conversion"
    )

    -- 0x0000000080000000: lower 32 bits = INT32_MIN as i32.
    test:is(smt:check(("(assert (= %s %s))"):format(
            arith_utils.smt_int_to_fp("#x0000000080000000"),
            arith_utils.const_num_to_smt_fp(-2^31)
        )), smt.result.SAT, "i32 sign-extend 0x80000000 -> FP -2^31"
    )
end)

test:test("mark_narrowed_refs", function(test)
    local ir_passes = require("ljopt.ir_passes")

    test:plan(3)

    local function ssa(n) return { _is_ssa = true, _v = n,
        is_ssa = function(self) return self._is_ssa end,
        get_ssa = function(self) return self._v end } end
    local function lit(s) return { _is_ssa = false, _v = s,
        is_ssa = function(self) return self._is_ssa end,
        get_lit = function(self) return self._v end } end
    local function node(opcode, type, sref, left, right)
        return {
            _sref = sref, _op = opcode, _type = type,
            _left = left, _right = right,
            get_ssa_reference = function(self) return self._sref end,
            get_opcode = function(self) return self._op end,
            get_type = function(self) return self._type end,
            get_left_op = function(self) return self._left end,
            get_right_op = function(self) return self._right end,
        }
    end
    local function fresh_ctx()
        return {
            te_stack = { narrowed_refs = {} }
        }
    end

    -- SLOAD-C -> LE -> LE. Only the first LE (direct SLOAD-C
    -- operand) is marked; the chained LE on its result is not
    -- (mark_narrowed_refs only propagates one hop from SLOAD-C).
    local ctx = fresh_ctx()
    ir_passes.mark_narrowed_refs({
        node('SLOAD', 'int', 1, lit('#5'), lit('CRI')),
        node('LE', 'int', 2, ssa(1), lit('#x7ffffffe')),
        node('LE', 'int', 3, ssa(2), lit('#x7ffffffe')),
    }, ctx)
    test:is(ctx.te_stack.narrowed_refs[2], true,
        "LE on SLOAD-C + const marked")
    test:is(ctx.te_stack.narrowed_refs[3], nil,
        "chained LE on non-SLOAD-C operand not marked")

    -- LE whose operand is a stray SSA ref (no SLOAD-C anywhere):
    -- not marked.
    ctx = fresh_ctx()
    ir_passes.mark_narrowed_refs({
        node('LE', 'int', 1, ssa(99), lit('#x7ffffffe')),
    }, ctx)
    test:is(ctx.te_stack.narrowed_refs[1], nil,
        "LE on stray ref not marked")
end)

test:test("utils trace ordering", function(test)
    test:plan(12)

    local file, line = utils.loc_key("foo.lua:42")
    test:is(file, "foo.lua", "loc_key file")
    test:is(line, 42, "loc_key line")
    file, line = utils.loc_key("no-location")
    test:is(file, "no-location", "loc_key no-line file")
    test:is(line, 0, "loc_key no-line line")

    test:is(utils.loc_less("a.lua:1", "b.lua:1"), true,
        "loc_less orders by file")
    test:is(utils.loc_less("b.lua:1", "a.lua:1"), false,
        "loc_less orders by file reversed")
    test:is(utils.loc_less("a.lua:2", "a.lua:10"), true,
        "loc_less compares lines numerically")
    test:is(utils.loc_less("a.lua:10", "a.lua:2"), false,
        "loc_less compares lines numerically reversed")
    test:is(utils.loc_less("x:01", "x:1"), true,
        "loc_less falls back to the string")

    test:is(utils.rjust(3, 5), "    3", "rjust number")
    test:is(utils.rjust("#1", 3), " #1", "rjust string")

    local order = utils.build_order(
        {[10] = true, [20] = true, [30] = true},
        {[10] = "b.lua:2", [20] = "a.lua:5", [30] = "a.lua:1"})
    test:is_deeply(order, {30, 20, 10}, "build_order sorts by location")
end)

test:test("utils solver helpers", function(test)
    test:plan(13)

    local backends = utils.solver_backends()
    test:is(#backends, 2, "solver_backends count")
    test:is(backends[1], ljopt_config.get_smt_solver(),
        "solver_backends preferred first")
    local names = {[backends[1]] = true, [backends[2]] = true}
    test:ok(names.z3 and names.cvc5, "solver_backends both backends")

    local solver = utils.find_solver()
    test:isnt(solver, nil, "find_solver returns a solver")
    test:is(type(solver.check), "function", "find_solver solver API")

    local t1 = utils.clock_monotonic()
    test:is(type(t1), "number", "clock_monotonic type")
    test:ok(utils.clock_monotonic() >= t1, "clock_monotonic monotonic")

    local mock = mock_solver()
    local widths = {tag_w = 2, counter_w = 4}
    local traces = {
        [1] = "UNSAT",
        [2] = "SAT",
        [3] = "UNKNOWN",
    }
    local verdict, status, solve_time
    local output = capture_stdout(function()
        verdict, status, solve_time =
            utils.check_trace(mock, traces, 1, 1, "a.lua:1", widths)
    end)
    test:is(verdict, "Passed", "check_trace UNSAT verdict")
    test:is(status, "passed", "check_trace UNSAT status")
    test:is(type(solve_time), "number", "check_trace UNSAT time")
    test:like(output, "Start", "check_trace prints the start line")

    capture_stdout(function()
        verdict = utils.check_trace(mock, traces, 2, 2, "b.lua:2",
            widths)
    end)
    test:is(verdict, "Failed", "check_trace SAT verdict")

    capture_stdout(function()
        verdict = utils.check_trace(mock, traces, 3, 3, "c.lua:3",
            widths)
    end)
    test:is(verdict, "Timeout", "check_trace UNKNOWN verdict")
end)

test:test("utils verification reporting", function(test)
    test:plan(13)

    local output = capture_stdout(function()
        utils.print_trace_line(1, 3, "a.lua:1", "Passed", 0.5,
            {nw = 1, tag_w = 2})
    end)
    test:like(output, "1/3 Trace #1", "print_trace_line prefix")
    test:like(output, "Passed", "print_trace_line verdict")
    test:like(output, "0%.50 sec", "print_trace_line time")

    output = capture_stdout(function()
        utils.print_report(1, 1, 1, {{idx = 2, loc = "b.lua:2"}},
            {{idx = 3, loc = "c.lua:3"}}, 3, utils.clock_monotonic())
    end)
    test:like(output, "33%% traces passed", "print_report percent")
    test:like(output, "The following traces FAILED",
        "print_report failed list")
    test:like(output, "b.lua:2 %(Failed%)", "print_report failed entry")
    test:like(output, "TIMED OUT", "print_report timeout list")
    test:like(output, "c.lua:3 %(Timeout%)", "print_report timeout entry")

    output = capture_stdout(function()
        utils.print_report(3, 0, 0, {}, {}, 3, utils.clock_monotonic())
    end)
    test:like(output, "100%% traces passed, 0 traces failed out of 3",
        "print_report without timeouts")
    test:unlike(output, "TIMED OUT", "print_report no timeout list")

    local exit_codes = {OK = 0, ERR_VERIFICATION_FAILED = 3,
        ERR_SMT_UNKNOWN = 4}
    local trace_locs = {[5] = "a.lua:1", [6] = "b.lua:2", [7] = "c.lua:3"}
    local mock = mock_solver()
    local rc
    capture_stdout(function()
        rc = utils.verify_traces(mock, {[5] = "UNSAT", [6] = "SAT",
            [7] = "UNKNOWN"}, trace_locs,
            {{idx = 1, uid = 5}, {idx = 2, uid = 6}, {idx = 3, uid = 7}},
            3, utils.clock_monotonic(), exit_codes)
    end)
    test:is(rc, exit_codes.ERR_VERIFICATION_FAILED,
        "verify_traces failed exit code")

    capture_stdout(function()
        rc = utils.verify_traces(mock, {[5] = "UNSAT"}, trace_locs,
            {{idx = 1, uid = 5}}, 3, utils.clock_monotonic(), exit_codes)
    end)
    test:is(rc, exit_codes.OK, "verify_traces passed exit code")

    capture_stdout(function()
        rc = utils.verify_traces(mock, {[7] = "UNKNOWN"}, trace_locs,
            {{idx = 1, uid = 7}}, 3, utils.clock_monotonic(), exit_codes)
    end)
    test:is(rc, exit_codes.ERR_SMT_UNKNOWN,
        "verify_traces timeout exit code")
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
