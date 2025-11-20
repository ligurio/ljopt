local utils = require("ljopt.utils")
local test = require("tests.tap").test("ljopt")

local function expect_fail(name, fun, ...)
    local success, _ = pcall(fun, ...)
    test:is(success, false, name)
end

test:plan(4)

test:test("merge_tables_named", function(test)
    test:plan(6)
    -- Test 1: Basic functionality with string keys
    local t1 = {a = 1, b = 2, c = 3}
    local t2 = {a = 10, b = 20, c = 30}
    local result = utils.merge_tables_named(t1, t2)
    test:is(result.a.value1, 1)
    test:is(result.b.value1, 2)
    test:is(result.c.value1, 3)
    test:is(result.a.value2, 10)
    test:is(result.b.value2, 20)
    test:is(result.c.value2, 30)

    -- Missing 'c'.
    expect_fail(utils.merge_tables_named,
        {a = 1, b = 2},
		{a = 1, b = 2, c = 3}, "Left missing c")
    expect_fail(utils.merge_tables_named,
	    {a = 1, b = 2, c = 3},
		{a = 1, b = 2}, "Right missing c")

    -- nil value.
    expect_fail(utils.merge_tables_named,
	    {a = nil},
		{a = 1}, "Left nil")
    expect_fail(utils.merge_tables_named,
	    {a = 1},
		{a = nil}, "Right nil")
end)
