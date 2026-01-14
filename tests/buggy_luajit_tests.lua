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
local coverage = require("tests.coverage")
local toggle_debug_hook = require('tests.coverage').toggle_debug_hook()

local buggy_build = os.getenv("BUGGY_BUILD") == "1"
local reproducers_path = coverage.cwd() .. "/tests/reproducers/"

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
coverage.enable()

test:plan(1)

-- The function executes the passed Lua chunk and returns
-- a boolean value - true if the result of execution is as
-- expected: the bug was reproduced on the problematic LuaJIT
-- version and the bug was not reproduced on the fixed LuaJIT
-- version and false otherwise.
local function reproduce_bug_in_runtime(chunk, err_msg)
    local fn = assert(load(chunk), "Lua chunk is broken")
    -- Enabled code coverage breaks LuaJIT compilation.
    toggle_debug_hook()
    local ok, err = pcall(fn)
    toggle_debug_hook()
    local expected_result = not buggy_build
    -- Default value is false, when LuaJIT build contains a bug.
    local err_is_matched = not buggy_build
    if buggy_build then
       assert(type(err) == "string", "error is not a string")
       err_is_matched = string.match(err, err_msg) ~= nil
    end
    return ok == expected_result and err_is_matched
end

-- The function records LuaJIT traces, translate every trace to
-- SMT-LIB formulas, check their SMT-LIB syntax and check that
-- SMT solver returns an expected result for produced formulas.
-- The function returns true if everything was succeed and false
-- otherwise. The function triggers an assertion if no SMT
-- formulas were produced.
local function reproduce_bug_using_smt(chunk)
    -- Enabled code coverage breaks LuaJIT compilation,
    -- `toggle_debug_hook()` disables using `debug.sethook()` in
    -- <ljopt/ir_dump.lua>.
    local formulas = ljopt.ir.traces_to_smt(chunk)
    assert(next(formulas) ~= nil, "no SMT formulas")
    for _, formula in pairs(formulas) do
        local smt_formula = smt_constants.LJOPT_SMTLIB .. formula
        if not smt:parse(smt_formula) then
            return false
        end
        local smt_res = buggy_build and smt.result.SAT or smt.result.UNSAT
        if smt:check(smt_formula) ~= smt_res then
            return false
        end
    end

    return true
end

local function read_reproducer_file(filename)
    local path = reproducers_path .. filename
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local buf = file:read("*a")
    file:close()
    return buf
end

-- https://github.com/LuaJIT/LuaJIT/pull/783
-- luacheck: push no max_comment_line_length
-- https://github.com/tarantool/luajit/commit/ab0c0793a43fc0fb0c7b71b6250339117d99254a
-- https://github.com/LuaJIT/LuaJIT/commit/7b994e0ee0399caf6319865bbac88ddf62129a36
-- luacheck: pop
test:test("Fix FOLD rule for x-0 (LuaJIT#783)", function(test)
    test:plan(2)
    local chunk = read_reproducer_file("lj_783.lua")
    test:ok(reproduce_bug_in_runtime(chunk,
        "-0 folding in simplify_numsub_k"), "reproduce in runtime")
    test:ok(reproduce_bug_using_smt(chunk), "reproduce using SMT")
end)

coverage.shutdown()

os.exit(test:check() == true and 0 or 1)
