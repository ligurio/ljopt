-- In this file we test all known bugs.
--
-- Specifically for this file we have old version of LuaJIT
-- which should generate not equivalent traces.
-- Tests here are similar to tests.lua,
-- but due to requirement of old LuaJIT compiler we extracted
-- them to separate file.

local ljopt = require("ljopt")
local smt = require("tests.smtlib2").new()
local test = require("tests.tap").test("ljopt")
local smt_constants = require('ljopt.smt_constants')

local buggy_build = os.getenv("BUGGY_BUILD")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

test:plan(1)

local function test_result_expected(test, id, formula)
    test:is(smt:parse(formula), true, "formula_" .. id .. " parsed")
    if buggy_build then
        test:is(smt:check(formula), smt.result.SAT, "test_buggy_luajit_" .. id)
    else
        test:is(smt:check(formula), smt.result.UNSAT, "test_correct_" .. id)
    end

end

-- luacheck: push no max_comment_line_length
-- https://github.com/LuaJIT/LuaJIT/commit/ab0c0793a43fc0fb0c7b71b6250339117d99254a
-- luacheck: pop
test:test("Test fold_signed_zero (LuaJIT#783)", function(test)
    local min_zero = [[
local function foo(a)
    return a - (-0.0)
end
foo(-0.0)
foo(-0.0)
foo(-0.0)
]]
    test:plan(2)

    local formulas = ljopt.ir.traces_to_smt(min_zero)
    for i, formula in pairs(formulas) do
        test_result_expected(test, i, smt_constants.LJOPT_SMTLIB .. formula)
    end
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
