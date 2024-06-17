local ljopt = require("ljopt")
local smt = require("tests.smtlib2").new()
local test = require("tests.tap").test("ljopt")

local function is_tarantool()
    return _G['_TARANTOOL'] ~= nil
end

if is_tarantool() then
    require('tests.coverage').enable()
end

if os.getenv('LJOPT_ENABLE_INTERNAL_CHECKS') == nil then
    os.execute('export LJOPT_ENABLE_INTERNAL_CHECKS=ON')
end

test:plan(5)

test:test("smt_module", function(test)
    test:plan(2)

    test:is(smt:parse("(declare-const p0 Bool)"), true, "SMT-LIB parsing")
    test:is(smt:check("(declare-const p0 Bool)"), 1, "SMT-LIB checking")
end)

test:test("ir_dump", function(test)
    test:plan(2)

    local traces = ljopt.ir.record("for i in 1, 100 do local a = 1 end")
    test:is(next(traces), nil, "lua code without traces")

    traces = ljopt.ir.record("for i = 1, 100 do local a, b = 23, 11; y = a + b end")
    test:isnt(next(traces), nil, "lua code with traces")
end)

test:test("bc_dump", function(_test)
    -- Empty.
end)

test:test("ir_smtlib", function(test)
    test:plan(4)

    local ok, err = pcall(ljopt.ir.translate, "")
    test:is(ok, false, "exit code is correct")
    test:like(err, "not a table", "error message is correct")

    local buf = ljopt.ir.translate({})
    test:is(type(buf), "string", "type of result when no traces")
    test:isnt(#buf, 0, "length of result when no traces")
end)

test:test("bc_smtlib", function(_test)
    -- Empty.
end)

if is_tarantool() then
    require('tests.coverage').shutdown()
end

os.exit(test:check() == true and 0 or 1)
