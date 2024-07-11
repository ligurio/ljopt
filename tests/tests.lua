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

test:plan(7)

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

local function translate_ir (lua_code, luajit_optimization_params)
    lua_code = luajit_optimization_params..'\n'..lua_code
    local traces = ljopt.ir.record(lua_code)
    local result = ''
    for i = 1, table.getn(traces) do
        if traces[i] and type(traces[i]) == "table" then
            result = result .. ljopt.ir.translate(traces[i])
        end
    end

    return result
end

test:test("fold_brol (LuaJIT#1079)", function(test)
    test:plan(4)

    local lua_sample =[[
local bit = require('bit');
for i = 1, 3 do
    assert(tonumber(bit.rol(bit.band(i, 127LL), 32)) ~= 0)
end
]]

    local ljopt
    ljopt = [[
    ljopt.flush();
    jit.opt.start(0, '-fold', '+cse', '+fwd', 'hotloop=1', 'hotexit=1');
    ]]
    local smtlib_disabled_fold = translate_ir(lua_sample, ljopt)
    test:isnt(smtlib_disabled_fold, nil, 'SMT-LIB with disabled fold')
    test:is(smt:parse(smtlib_disabled_fold), true,
            'SMT-LIB with disabled fold is correct')

    ljopt = [[
    ljopt.flush();
    jit.opt.start(0, '+fold', '+cse', '+fwd', 'hotloop=1', 'hotexit=1');
    ]]
    local smtlib_enabled_fold = translate_ir(lua_sample, ljopt)
    test:isnt(smtlib_enabled_fold, nil, 'SMT-LIB with enabled fold')
    test:is(smt:parse(smtlib_enabled_fold), true,
            'SMT-LIB with enabled fold is correct')
end)

test:test("fold_signed_zero (LuaJIT#783)", function(test)
    test:plan(4)

    local lua_sample = [[
local minus_zero = -0
local results = {}
for i = 1, 100 do
    local lhs = minus_zero
    local rhs = -1.0*(2^1016) * 0.
    results[i] = lhs - rhs
end
]]

    local ljopt
    ljopt = [[
    ljopt.flush();
    jit.opt.start(0, '-fold', '+cse', '+fwd', 'hotloop=1', 'hotexit=1');
    ]]
    local smtlib_disabled_fold = translate_ir(lua_sample, ljopt)
    test:isnt(smtlib_disabled_fold, nil, 'SMT-LIB output with disabled fold')
    test:is(smt:parse(smtlib_disabled_fold), true,
            'SMT-LIB with disabled fold is correct')

    ljopt = [[
    ljopt.flush();
    jit.opt.start(0, '+fold', '+cse', '+fwd', 'hotloop=1', 'hotexit=1');
    ]]
    local smtlib_enabled_fold = translate_ir(lua_sample, ljopt)
    test:isnt(smtlib_enabled_fold, nil, 'SMT-LIB output with enabled fold')
    test:is(smt:parse(smtlib_enabled_fold), true,
            'SMT-LIB with enabled fold is correct')
end)

test:test("bc_smtlib", function(_test)
    -- Empty.
end)

if is_tarantool() then
    require('tests.coverage').shutdown()
end

os.exit(test:check() == true and 0 or 1)
