local ljopt = require("ljopt")
local test = require("tests.tap").test("ljopt")

local function is_tarantool()
    return _G['_TARANTOOL'] ~= nil
end

if is_tarantool() then
    require('tests.coverage').enable()
end

test:plan(4)

test:test("ir_dump", function(test)
    test:plan(1)

    local traces = ljopt.ir.record("for i in 1, 100 do local a = 1 end")
    test:is(#traces, 1)
end)

test:test("bc_dump", function(_test)
    -- Empty.
end)

test:test("ir_smtlib", function(_test)
    -- Empty.
end)

test:test("bc_smtlib", function(_test)
    -- Empty.
end)

if is_tarantool() then
    require('tests.coverage').shutdown()
end

os.exit(test:check() == true and 0 or 1)
