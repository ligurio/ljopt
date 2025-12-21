-- This file contains general unit tests
-- to tests correctnes of arbitrary
-- data structures we use.

local utils = require("ljopt.utils")
local test = require("tests.tap").test("ljopt")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

local function expect_fail(test, name, fun, ...)
    local success, _ = pcall(fun, ...)
    test:is(success, false, name)
end

test:plan(1)

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
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
