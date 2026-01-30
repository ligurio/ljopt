-- This file contains all end-to-end tests.
-- Usually test has as an input a string on Lua,
-- and has an output as a SMT formula.

local ljopt = require("ljopt")
local ljopt_config = require("ljopt.config")
local smt = require("tests.smtlib2").new()
local smt_constants = require("ljopt.smt_constants")
local test = require("tests.tap").test("ljopt")
local utils = require("ljopt.utils")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

-- Apparently functions sandboxed by `setfenv` could
-- not call `jit.opt.*`, that's why we should wrap
-- call to `record` with manual presetting JIT options.
local function record_code(lua_code, opt)
    if opt == nil then
        opt = "jit.opt.start(0, 'hotloop=1', 'hotexit=1')"
    end
    assert(load(opt))()
    -- Flush JIT so we'll have consistent
    -- trace numbers across recordings.
    jit.flush()
    local exec_records = ljopt.ir.record(lua_code)
    assert(type(exec_records) == 'table')
    return exec_records
end


test:plan(13)

test:test("smt_module", function(test)
    test:plan(2)

    test:is(smt:parse("(declare-const p0 Bool)"), true, "SMT-LIB parsing")
    test:is(smt:check("(declare-const p0 Bool)"),
        smt.result.SAT, "SMT-LIB checking"
    )
end)

test:test("ir_dump", function(test)
    test:plan(2)

    -- XXX: Flushing the whole cache of compiled code helps to fix
    -- a flaky testcase below ("lua code without traces").
    jit.flush()
    local traces = ljopt.ir.record("for i in 1, 100 do local a = 1 end")
    test:is(next(traces), nil, "lua code without traces")

    traces = ljopt.ir.record(
        "for i = 1, 100 do local a, b = 23, 11; y = a + b end"
    )
    test:isnt(next(traces), nil, "lua code with traces")
end)

test:test("bc_dump", function(_test)
    -- Empty.
end)

test:test("ir_smtlib", function(test)
    test:plan(2)

    local buf = ljopt.ir.translate_to_smt("")
    test:is(type(buf), "string", "type of result when no traces")
    test:is(#buf, 0, "length of result when no traces")
end)

local function translate_ir (lua_code, luajit_optimization_params)
    lua_code = luajit_optimization_params..'\n'..lua_code
    return ljopt.ir.translate_to_smt(lua_code)
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

-- Snapshot parsing tests
test:test("Snapshot tests", function(test)
    local src = [[
local function f(y)
  return y, y + 1
end
f(0)
f(1)
f(1)
]]
    -- Later we check, that parsed exactly
    -- SNAP   #0   [ ---- ---- ]
    -- SNAP   #1   [ ---- ---- 0001 0003 ]
    test:plan(6)
    local exec_state = record_code(src)
    for _k, trace in pairs(exec_state) do
        for _snapno, snap in pairs(trace.snapshots) do
            if (table.getn(snap.slots) ~= 0) then
                test:is(snap.slots[1][1], 2, "Incorrect slot")
                test:is(
                    snap.slots[1][2], "ssa", "Incorrect snapshot entry type"
                )
                test:is(snap.slots[1][3], 1, "Incorrect entry value")

                test:is(snap.slots[2][1], 3, "Incorrect slot")
                test:is(
                    snap.slots[2][2], "ssa", "Incorrect snapshot entry type"
                )
                test:is(snap.slots[2][3], 3, "Incorrect entry value")
            end
        end
    end
end)

-- IR flags parsing tests.
test:test("IR flags parsing tests.", function(test)
    local src = [[
local LOOP_LIMIT=2
for idx = 1, 4 do
    local tab = { idx }
    if idx > LOOP_LIMIT then break end
end
]]
    test:plan(6)

    -- We get phi instruction only on optimized trace.
    local exec_state = record_code(src, "jit.opt.start(3, 'hotloop=1')")
    -- Our trace is always number 2 (line number).
    local trace = exec_state[2].trace

    test:is(trace[9].flags.irt_isphi, true, "9-th instruction is a phi")
    test:is(trace[6].flags.irt_mark, true, "6-th instruction is marked")
    test:is(trace[7].flags.irt_guard, true, "7-th instruction is a guard")

    -- Ensure sometimes these flags are false.
    test:is(trace[1].flags.irt_isphi, false, "1-st instruction is not phi")
    test:is(trace[1].flags.irt_mark, false, "1-st instruction is not marked")
    test:is(trace[1].flags.irt_guard, false, "1-st instruction is not guard")
end)

-- Trace exits parsing tests.
test:test("Trace exit tests", function(test)
    local src = [[
local function f()
  local x = 0
  local y = 0
  return x + y
end
f(0)
f(1)
f(1)
]]
    -- Later we check, that parsed exactly
    -- SNAP   #0   [ ---- ---- ]
    -- 0001 >  int ADDOV  #x0000000000000000  #x0000000000000000
    -- SNAP   #1   [ ---- ---- 0001 0003 ]
    test:plan(10)

    local exec_state = record_code(src)
    -- Our trace is always number 1.
    local trace = exec_state[1]

    test:is(
        trace.trace[1].flags.irt_guard, true, "First instruction is a guard"
    )

    test:is(#exec_state, 1, "No more traces")
    utils.enrich_snapshots_with_exits(trace)

    -- 1 and 4 is bytecode offset of each snapshot.
    test:is(#trace.snapshots[1].slots, 0, "First snapshot empty")

    test:is(#trace.snapshots[4].slots, 1, "Second snapshot has return value")
    local return_slots = trace.snapshots[4].slots
    test:is(return_slots[1][1], 3, "Incorrect slot")
    test:is(return_slots[1][2], "ssa", "Incorrect snapshot entry type")
    test:is(return_slots[1][3], 2, "Incorrect entry value")

    test:is(#trace.snapshots[1].exits, 1, "Single exit")
    test:is(trace.snapshots[1].exits[1], 1, "Exit by first instruction")

    test:is(#trace.snapshots[4].exits, 0, "No exits")
end)

-- Main tests for traces equivalence.
test:test("ir_smtlib", function(test)
    local srcs = { [[
local function f(y)
  return y - y, y + y, y * y, y / y
end
f(0)
f(1)
f(1)
]], [[
local function f(y)
  -- The numbers are arbitrary.
  local x = 11
  local y = 23
  return x + y, x * y, x / y, x - y
end
f(0)
f(1)
f(1)
]],
[[
local function f(x)
  return x + 0.23, x > 0.23, x < 0.23, x >= 0.23, x <= 0.23, x - 0.23, x / 0.23, x * 0.23
end
f(0.1)
f(1.2)
f(1.2)
]]}
-- -- Add when PR never-fail merged andSnapshot
-- -- matching is not strict.
-- -- https://github.com/ligurio/ljopt/issues/32
-- local function foo(c)
--   c = c + 1.1;
--   -- UGE num test
--   if c > 5 then return c end
--   return 0
-- end
-- foo(1.1)
-- foo(1.2)
    test:plan(2 * #srcs)

    for i, f in ipairs(srcs) do
        local formulas = ljopt.ir.traces_to_smt(f)
        for j, formula in ipairs(formulas) do
            formula = smt_constants.LJOPT_SMTLIB .. formula
            test:is(smt:parse(formula), true,
                ("test_%s trace %d parse."):format(i, j))
            test:is(smt:check(formula), smt.result.UNSAT,
                ("test_%d trace %d check."):format(i, j))
        end
    end
end)

test:test("Sandbox Lua chunk", function(test)
    test:plan(1)
    local overwrite_global = [[
-- Ensure Lua chunk sandboxed.
type = nil
debug.setmetatable("string", nil)
local function foo()
    return 1
end
foo()
foo()
]]
    local formulas = ljopt.ir.traces_to_smt(overwrite_global)

    -- Trace id is 4.
    local formula = smt_constants.LJOPT_SMTLIB .. formulas[4]
    -- Testing formula is redundant.
    -- What matters is that we do not crashed on parsing traces.
    test:is(smt:parse(formula), true, "Sandbox parsing.")
end)

test:test("Stitching test", function(test)
    -- Stitching sometimes generates 2 traces, that's why it
    -- separated from the tests above. Only main trace have
    -- interesting `Snapshot`, so we need to test only main trace.
    test:plan(2)
    local stitching = [[
-- This example needed to ensure stitching works correctly.
local math = require("math")
local function f()
    local x = 123
    -- Causes stitching.
    math.modf(x)
    return x
end

f()
f()
f()
]]
    -- Disable strict mode. Stitching uses `print`, which
    -- translates to `IRNodeSLOADFun` which is not implemented.
    local strict_mode = ljopt_config.is_strict_mode()
    ljopt_config.set_strict_mode(false)

    local formulas = ljopt.ir.traces_to_smt(stitching)

    -- Trace id is always: 3.
    local formula = smt_constants.LJOPT_SMTLIB .. formulas[3]
    test:is(smt:parse(formula), true, "Stitching parsing.")
    test:is(smt:check(formula), smt.result.UNSAT, "Stitching test checking.")

    ljopt_config.set_strict_mode(strict_mode)
end)

test:test("bc_smtlib", function(_test)
    -- Empty.
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
