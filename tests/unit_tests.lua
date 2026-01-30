-- This file contains general unit tests
-- to tests correctnes of arbitrary
-- data structures we use.

local arith_utils = require("ljopt.ir.arith_utils")
local ljopt_config = require("ljopt.config")
local utils = require("ljopt.utils")

local smt = require("tests.smtlib2").new()
local test = require("tests.tap").test("ljopt")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

local function expect_fail(test, name, fun, ...)
    local success, _ = pcall(fun, ...)
    test:is(success, false, name)
end

test:plan(3)

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

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
