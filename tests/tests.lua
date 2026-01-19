-- This file contains all end-to-end tests.
-- Usually test has as an input a string on Lua,
-- and has an output as a SMT formula.

local ljopt = require("ljopt")
local smt = require("ljopt.smtlib2").new()
local test = require("tests.tap").test("ljopt")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

test:plan(7)

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
    test:is(type(buf), "table", "type of result when no traces")
    test:is(#buf, 0, "length of result when no traces")
end)

-- Snapshot parsing tests
test:test("Snapshot tests", function(test)
    local src = [[
jit.opt.start(0, 'hotloop=1', 'hotexit=1');
local function f(y)
  return y, y + 1
end
f(0)
f(1)
]]
    -- Later we check, that parsed exactly
    -- SNAP   #0   [ ---- ---- ]
    -- SNAP   #1   [ ---- ---- 0001 0003 ]
    test:plan(6)
    local exec_state = ljopt.ir.record(src)
    for _k, trace in pairs(exec_state) do
        for _snapno, snap in pairs(trace.snapshots) do
            if (table.getn(snap) ~= 0) then
                test:is(snap[1][1], 2, "Incorrect slot")
                test:is(snap[1][2], "ssa", "Incorrect snapshot entry type")
                test:is(snap[1][3], 1, "Incorrect entry value")

                test:is(snap[2][1], 3, "Incorrect slot")
                test:is(snap[2][2], "ssa", "Incorrect snapshot entry type")
                test:is(snap[2][3], 3, "Incorrect entry value")
            end
        end
    end
end)

-- Main tests for traces equivalence.
test:test("ir_smtlib", function(test)
    local srcs = { [[
local function f(y)
  return y - y, y + y, y * y, y / y
end
f(0)
f(1)
]], [[
local function f(y)
  -- The numbers are arbitrary.
  local x = 11
  local y = 23
  -- SUBOV is not supported yet
  return x + y, x * y, x / y --, x - y
end
f(0)
f(1)
]]}
    test:plan(2 * #srcs)

    for i, f in ipairs(srcs) do
        local formulas = ljopt.ir.traces_to_smt(f)
        for j, formula in ipairs(formulas) do
            test:is(smt:parse(formula), true,
                ("test_%s trace %d parse."):format(i, j))
            test:is(smt:check(formula), smt.result.UNSAT,
                ("test_%d trace %d check."):format(i, j))
        end
    end
end)

test:test("bc_smtlib", function(_test)
    -- Empty.
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
