-- This file contains all end-to-end tests.
-- Usually test has as an input a string on Lua,
-- and has an output as a SMT formula.

local ljopt = require("ljopt")
local ljopt_config = require("ljopt.config")
local smt = require("tests.smtlib2").new()
local ir_dump_utils = require("ljopt.ir_dump_utils")
local smt_constants = require("ljopt.smt_constants")
local ir_smtlib = require("ljopt.ir_smtlib")
local loop_unrolling = require("ljopt.loop_unrolling")
local op_type = require("ljopt.ir.op_type")
local test = require("tests.tap").test("ljopt")

-- The suite runs strict: an unimplemented node should fail a
-- test rather than quietly shrink the formula it was meant to
-- prove something about. Blocks that need a chunk ljopt cannot
-- fully model turn it off around themselves.
ljopt_config.set_strict_mode(true)

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

-- Apparently functions sandboxed by `setfenv` could
-- not call `jit.opt.*`, that's why we should wrap
-- call to `record` with manual presetting JIT options.
local function record_code(lua_code, opt)
    local exec_records = ljopt.ir.record(lua_code, opt)
    local traces_map = ir_dump_utils.ljopt_get_traceid_map()
    assert(type(exec_records) == 'table')
    return exec_records, traces_map
end

-- Check that expected instructions are present and implemented
-- (not filtered as NYI) in the recorded traces.
-- @expected_ins - array of {name, type} in expected order
-- @lua_code - chunk to test
-- Returns (true, nil) if all instructions found in order
-- and (false, <err>) otherwise.
local function check_ins_present(lua_chunk, expected_ins, opt)
    local exec_records = record_code(lua_chunk, opt)
    for _, trace in pairs(exec_records) do
        trace.trace, trace.snapshots = loop_unrolling.loop_unrooling_transform(
            trace.trace, trace.snapshots, trace.linktype
        )
        local nodes = ir_smtlib.construct_nodes(trace)
        local ni = 1
        for _, instr in ipairs(expected_ins) do
            local found = false
            local function op_matches(op, expected)
                if expected == nil then return true end
                return op ~= nil and op._value == expected._value
            end
            while ni <= #nodes do
                local node = nodes[ni]
                ni = ni + 1
                if node:get_opcode() == instr.name
                    and node:get_type() == instr.type
                    and op_matches(node:get_left_op(), instr.left_op)
                    and op_matches(node:get_right_op(), instr.right_op)
                then
                    found = true
                    break
                end
            end
            if not found then
                return false,
                    ("Instruction %s(%s,%s,%s) not found"):format(
                        instr.name, instr.type or "*",
                        instr.left_op
                            and op_type.to_string(instr.left_op) or "*",
                        instr.right_op
                            and op_type.to_string(instr.right_op) or "*"
                    )
            end
        end
    end
    return true
end

test:plan(11)

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

test:test("ir_smtlib", function(test)
    test:plan(2)

    local buf = ljopt.ir.translate_to_smt("")
    test:is(type(buf), "string", "type of result when no traces")
    test:is(#buf, 0, "length of result when no traces")
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
                    snap.slots[1][2].type, "ssa",
                    "Incorrect snapshot entry type"
                )
                test:is(
                    snap.slots[1][2].value, 1,
                    "Incorrect entry value"
                )

                test:is(snap.slots[2][1], 3, "Incorrect slot")
                test:is(
                    snap.slots[2][2].type, "ssa",
                    "Incorrect snapshot entry type"
                )
                test:is(
                    snap.slots[2][2].value, 3,
                    "Incorrect entry value"
                )
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

    local exec_state, traces_map = record_code(
        src, "jit.opt.start(3, 'hotloop=1')"
    )
    -- Our trace id is always: 1.
    local trace = exec_state[traces_map[1]].trace

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
f(1)
f(1)
]]
    -- Later we check, that parsed exactly
    -- SNAP   #0   [ ---- ---- ]
    -- 0001 >  int ADDOV  #x0000000000000000  #x0000000000000000
    -- SNAP   #1   [ ---- ---- 0001 0003 ]
    test:plan(6)

    local exec_state, traces_map = record_code(src)
    -- Our trace id is always: 1.
    local trace = exec_state[traces_map[1]]

    test:is(
        trace.trace[1].flags.irt_guard, true, "First instruction is a guard"
    )

    -- 1 and 4 is bytecode offset of each snapshot.
    test:is(#trace.snapshots[1].slots, 0, "First snapshot empty")

    test:is(#trace.snapshots[4].slots, 1, "Second snapshot has return value")
    local return_slots = trace.snapshots[4].slots
    test:is(return_slots[1][1], 3, "Incorrect slot")
    test:is(
        return_slots[1][2].type, "ssa",
        "Incorrect snapshot entry type"
    )
    test:is(
        return_slots[1][2].value, 2,
        "Incorrect entry value"
    )
end)

-- Main tests for traces equivalence.
test:test("ir_smtlib", function(test)
    local srcs = { {
        code = [[
local function f(y)
  return y - y, y + y, y * y, y / y
end
f(0)
f(1)
f(1)
f(1)
f(1)
f(1)
f(1)
f(1)
]],
        ins = {
            {type = "num", name = "SLOAD"},
            {type = "num", name = "SUB"},
            {type = "num", name = "ADD"},
            {type = "num", name = "MUL"},
            {type = "num", name = "DIV"},
        },
    }, {
        code = [[
local function f(y)
  -- The numbers are arbitrary.
  local x = 11
  local y = 23
  return x + y, x * y, x / y, x - y
end
f(0)
f(1)
f(1)
f(1)
f(1)
f(1)
f(1)
f(1)
]],
        ins = {
            {type = "int", name = "ADDOV"},
            {type = "num", name = "MUL"},
            {type = "num", name = "DIV"},
            {type = "int", name = "SUBOV"},
        },
    }, {
        code = [[
local function f(x)
  return x + 0.23, x > 0.23, x < 0.23, x >= 0.23, x <= 0.23, x - 0.23, x / 0.23, x * 0.23
end
-- This test requires more calls for some reason.
f(1.3)
f(1.3)
f(1.3)
f(1.3)
f(1.3)
f(1.3)
f(1.3)
f(1.3)
f(1.3)
f(2.3)
f(2.3)
]],
        ins = {
            {type = "num", name = "SLOAD"},
            {type = "num", name = "ADD"},
            {type = "num", name = "LT"},
            {type = "num", name = "UGE"},
            {type = "num", name = "LE"},
            {type = "num", name = "UGT"},
            {type = "num", name = "SUB"},
            {type = "num", name = "DIV"},
            {type = "num", name = "MUL"},
        },
    }, {
        code = [[
-- str.len test.
local function foo()
    return #"123"
end
foo()
foo()
foo()
foo()
]],
        ins = {
            -- int FLOAD str.len
            {type = "int", name = "FLOAD"}
        },
    }, {
        code = [[
local function foo(c)
  return 1 == c
end
foo(1)
foo(1)
foo(1)
]],
        ins = {
            {type = "num", name = "CONV"},
            {type = "num", name = "EQ"}
        },
    }, {
        name = "EQ on function references",
        code = [[
local mf = math.floor
local function h(x) return mf(x) * 2 end
h(1.5)
h(2.5)
h(3.5)
]],
        ins = {
            {type = "fun", name = "EQ"},
        },
    }, {
        code = [[
local x = 12
for i = 1, 100 do
    x = x + 5
end
]],
        ins = {
            {type = "num", name = "ADD"},
            {type = "num", name = "ADD"},
            {type = "num", name = "ADD",
                -- Check that ADD argument is
                -- previous loop iteration output.
                left_op = op_type.new("ssa", 4)},
        },
    }, {
        code = [[
local x = 12
for i = 1, 100 do
    x = x + 5
end
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1', '-narrow')",
        ins = {
            {type = "num", name = "ADD"},
            {type = "num", name = "ADD"},
            {type = "num", name = "ADD",
                -- Make sure phi is correct when optimizations
                -- enabled.
                left_op = op_type.new("ssa", 3)},
        },
    }, {
        -- math.random goes through a helper that takes the
        -- lua_State, which records as CALLS. It was NYI, so the
        -- call and the value it produced left the formula.
        name = "lua_State helper called through CALLS",
        code = [[
local r = math.random
local x = 0
for i = 1, 40 do x = r() end
]],
        unroll_n = 1,
        ins = {
            {type = "num", name = "CALLS"},
        },    }, {
        -- Reading `...` inside the function that owns it records
        -- VLOAD over an AREF into the vararg region, reached by
        -- frame arithmetic from REF_BASE rather than through a
        -- table. All of it was NYI, so the loop body was empty.
        name = "vararg slots read through VLOAD",
        code = [[
local function foo(...)
    local s = 0
    for i = 1, 200 do
        local a, b = ...
        s = s + a + b
    end
    return s
end
foo(3, 4)
]],
        unroll_n = 1,
        ins = {
            {type = "p32", name = "AREF"},
            {type = "num", name = "VLOAD"},
        },    }, {
        -- string.sub lowers to STRREF + SNEW. Both were NYI, so
        -- the slice and everything reading it -- including the
        -- str.len of the result -- left the formula. -O3 folds
        -- the slice away, so unsat says the modelled substring
        -- is what the optimizer computed.
        name = "string.sub through STRREF and SNEW",
        code = [[
local sub = string.sub
local s = "hello world"
local acc = 0
for i = 1, 30 do
    acc = acc + #sub(s, 2, 4)
end
]],
        unroll_n = 1,
        ins = {
            {type = "p32", name = "STRREF"},
            {type = "str", name = "SNEW"},
            {type = "int", name = "FLOAD"},
        },    }, {
        -- Comparing two interned strings records as a str-typed
        -- guard. Without a class for that type variant the guard
        -- was dropped, and with it the branch it decides.
        code = [[
local function foo(s, u)
    if s == u then return 1 end
    return 2
end
foo("aa", "bb")
foo("aa", "bb")
foo("aa", "bb")
]],
        ins = {
            {type = "str", name = "NE"},
        },    }, {
        -- A constructor with constant contents records as TDUP,
        -- and the read that follows is an ABC against the size
        -- the template was built with. -O3 drops the copy and
        -- folds the read, so unsat says the modelled copy holds
        -- what the optimizer folded to.
        code = [[
local function foo(i)
    local t = {10, 20, 30}
    return t[i] + t[1]
end

foo(1)
foo(2)
foo(3)
]],
        ins = {
            {type = "tab", name = "TDUP"},
            {type = "int", name = "FLOAD"},
            {type = "int", name = "ABC"},
            {type = "num", name = "ALOAD"},
        },
--[[
    }, {
-- Fix BV <-> FP casts, now it's too slow:
-- https://github.com/ligurio/ljopt/issues/57
        code = [[
local bit = require("bit")
local function foo(x)
    return bit.tobit(x), bit.band(x, 0xff), bit.bnot(x),
           bit.bswap(x), bit.lshift(x, 2), bit.rshift(x, 2),
           bit.arshift(x, 2), bit.rol(x, 2)
end
foo(1.5)
foo(1.5)
foo(1.5)
\]\],
        ins = {
            {type = "int", name = "TOBIT"},
            {type = "int", name = "BAND"},
            {type = "int", name = "BNOT"},
            {type = "int", name = "BSWAP"},
            {type = "int", name = "BSHL"},
            {type = "int", name = "BSHR"},
            {type = "int", name = "BSAR"},
            {type = "int", name = "BROL"},
        },
]]
    }}
    test:plan(3 * #srcs)

    for i, f in ipairs(srcs) do
        local label = f.name or ("test_%d"):format(i)
        local ok, err = check_ins_present(f.code, f.ins, f.opt)
        test:ok(ok, ("%s instructions present: %s"):format(
            label, err or "ok"
        ))
        local formulas = ljopt.ir.traces_to_smt(f.code)
        for j, formula in pairs(formulas) do
            formula = smt_constants.LJOPT_SMTLIB .. formula
            test:is(smt:parse(formula), true,
                ("%s trace %s parse."):format(label, j))
            test:is(smt:check(formula), smt.result.UNSAT,
                ("%s trace %s check."):format(label, j))
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
foo()
foo()
foo()
foo()
]]
    local formulas = ljopt.ir.traces_to_smt(overwrite_global)

    -- Trace id is 1.
    local id = ir_dump_utils.ljopt_get_traceid_map()[1]
    local formula = smt_constants.LJOPT_SMTLIB .. formulas[id]
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
f()
f()
]]
    -- Disable strict mode. Stitching uses `print`, which
    -- translates to `IRNodeSLOADFun` which is not implemented.
    local strict_mode = ljopt_config.is_strict_mode()
    ljopt_config.set_strict_mode(false)

    local formulas = ljopt.ir.traces_to_smt(stitching)

    -- Trace id is always: 1.
    local id = ir_dump_utils.ljopt_get_traceid_map()[1]
    local formula = smt_constants.LJOPT_SMTLIB .. formulas[id]
    test:is(smt:parse(formula), true, "Stitching parsing.")
    test:is(smt:check(formula), smt.result.UNSAT, "Stitching test checking.")

    ljopt_config.set_strict_mode(strict_mode)
end)

-- The `narrow` optimization loads a number-typed slot as `int`
-- at -O3 but `num` at -O0. Unless the trace ID (derived from
-- SLOAD IR types) treats the two as equivalent, the -O0 and -O3
-- traces get different IDs and the pair is silently dropped.
-- See: https://github.com/ligurio/ljopt/issues/34
test:test("Trace IDs match across narrowing (LJOPT#34)", function(test)
    test:plan(2)
    local narrowing = [[
local function foo(n)
    local s = 0
    for i = 1, n do
        s = s + i
    end
    return s
end
for k = 1, 100 do foo(200) end
]]

    local function trace_id_set(opt)
        local exec_records = ljopt.ir.record(narrowing, opt)
        local ids = {}
        for id in pairs(exec_records) do
            ids[id] = true
        end
        return ids
    end

    local strict_mode = ljopt_config.is_strict_mode()
    ljopt_config.set_strict_mode(false)

    local unopt = trace_id_set("jit.opt.start(0, 'hotloop=1', 'hotexit=1')")
    -- Narrowing left enabled on purpose - that's the whole point.
    local opt = trace_id_set("jit.opt.start(3, 'hotloop=1', 'hotexit=1')")

    ljopt_config.set_strict_mode(strict_mode)

    test:ok(next(unopt) ~= nil, "recorded at least one trace")

    local matched = true
    for id in pairs(unopt) do
        if not opt[id] then
            matched = false
        end
    end
    test:ok(matched, "every -O0 trace id is present in -O3 (narrowing)")
end)

-- Relaxed mode tests, which means any code or
-- instructions can be placed here, we will ignore unimplemented
-- ones.
test:test("Tests for traces equivalence in relaxed mode", function(test)

    -- Disable strict mode.
    local strict_mode = ljopt_config.is_strict_mode()
    ljopt_config.set_strict_mode(false)

    local srcs = { {
        code = [[
local function foo(c)
  c = c + 1.1;
  -- UGE num test
  if c > 5 then return c end
  return 0
end
foo(1.1)
foo(1.1)
foo(1.1)
foo(1.1)
foo(1.1)
foo(1.1)
]],
        ins = {
            {type = "num", name = "SLOAD"},
            {type = "num", name = "ADD"},
            {type = "num", name = "UGE"},
        },
    }, {
        code = [[
-- Multiple hash keys (TNEW, NEWREF, HSTORE)
local function foo(x)
    x["a"] = 1
    x["b"] = 2
    return x
end

foo({})
foo({})
foo({})
]],
        ins = {
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
        },
    }, {
        code = [[
-- Hash store and load numeric value (HREFK, HSTORE, HLOAD)
local function foo(x)
    x["key"] = 42
    local v = x["key"]
    return v
end

foo({})
foo({})
foo({})
]],
        ins = {
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "HREFK"},
            {type = "num", name = "HLOAD"},
        },
    }, {
        code = [[
-- Array part store (AREF, ASTORE)
local function foo(x)
    x[1] = 10
    x[2] = 20
    return x
end

foo({})
foo({})
foo({})
]],
        ins = {
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "AREF"},
            {type = "num", name = "ASTORE"},
        },
    }, {
        code = [[
-- Array store and load (AREF, ASTORE, ALOAD)
local function foo(x)
    x[1] = 100
    local v = x[1]
    return v
end

foo({})
foo({})
foo({})
]],
        ins = {
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "AREF"},
            {type = "num", name = "ALOAD"},
        },
    }, {
        code = [[
-- TNEW test
local function foo()
    local x = {}
    x["a"] = 1
    return x
end

foo()
foo()
foo()
]],
        ins = {
            {type = "tab", name = "TNEW"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
        },
    }, {
        code = [[
-- Multiple hash keys (TNEW, NEWREF, HSTORE)
local function foo()
    local x = {}
    x["a"] = 1
    x["b"] = 2
    x["c"] = 3
    return x
end

foo()
foo()
foo()
]],
        ins = {
            {type = "tab", name = "TNEW"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
        },
    }, {
        code = [[
-- Table constructor with array part (TNEW, ASTORE)
local function foo(y)
    local x = {y, y + 1, y + 2}
    return x
end

foo(1)
foo(2)
foo(3)
foo(4)
]],
        ins = {
            {type = "tab", name = "TNEW"},
            {type = "num", name = "ASTORE"},
            {type = "num", name = "ASTORE"},
            {type = "num", name = "ASTORE"},
        },
    }, {
        code = [[
-- HSTORE tab (store table in table)
local function foo(x, y)
    x["key"] = y
    return x
end
foo({}, {})
foo({}, {})
foo({}, {})
]],
        ins = {
            {type = "p32", name = "NEWREF"},
            {type = "tab", name = "HSTORE"},
        },
    }, {
        code = [[
-- HSTORE nil (delete key)
local function foo(x)
    x["key"] = nil
    return x
end
foo({key=1})
foo({key=1})
foo({key=1})
]],
        ins = {
            {type = "nil", name = "HSTORE"},
        },
    }, {
        code = [[
-- HLOAD str
local function foo(x)
    return x["key"]
end
foo({key="hello"})
foo({key="hello"})
foo({key="hello"})
]],
        ins = {
            {type = "str", name = "HLOAD"},
        },
    }, {
        code = [[
-- EQ i64
local function foo(a, b)
    return a == b
end
foo(5LL, 5LL)
foo(5LL, 5LL)
foo(5LL, 5LL)
]],
        ins = {
            {type = "i64", name = "EQ"},
        },
    }, {
        code = [[
local bit = require('bit');
local function foo()
    return bit.rol(127LL, 1LL) ~= 0, bit.ror(127LL, 1LL) ~= 0
end
foo()
foo()
foo()
]],
        ins = {
            {type = "int", name = "CONV"},
            {type = "i64", name = "BROL"},
            {type = "i64", name = "BROR"},
            {type = "cdt", name = "CNEWI"}
        }
    }, {
        code = [[
-- CNEWI + FLOAD cdata.int64
local ffi = require("ffi")
local function foo()
    local v = ffi.new("int64_t", 42)
    return 42LL + 1LL, v + 1LL
end
foo()
foo()
foo()
]],
        ins = {
            {type = "i64", name = "CONV"},
            {type = "cdt", name = "CNEWI"},
            {type = "i64", name = "ADD"},
            {type = "cdt", name = "CNEWI"},
            {type = "i64", name = "ADD"},
            {type = "cdt", name = "CNEWI"},
        }
    }, {
        code = [[
-- CNEW: variable-length cdata. ffi.typeof("uint8_t[?]") boxes an
-- aggregate whose size is only known at run time, so the size
-- operand is an SSA value and the box lowers to CNEW (not the
-- scalar CNEWI). Exercises CNEW's runtime-size dispatch and the
-- ctype-id store; the unopt and opt traces must stay equivalent.
local ffi = require('ffi')
local vla_t = ffi.typeof("uint8_t[?]")
local t = {}
local function f(i) t[i] = vla_t(1) end
f(1)
f(2)
f(3)
]],
        ins = {
            {type = "cdt", name = "CNEW"},
        },
    }, {
        code = [[
-- String concatenation (BUFHDR, BUFPUT, BUFSTR)
local function foo(a, b)
    return a .. b
end

foo("hello", " world")
foo("hello", " world")
foo("hello", " world")
]],
        ins = {
            {type = "p32", name = "BUFHDR"},
            {type = "p32", name = "BUFPUT"},
            {type = "p32", name = "BUFPUT"},
            {type = "str", name = "BUFSTR"},
        },
    }, {
        code = [[
local sink
local function foo(a, b, c)
    local x = a .. b
    sink = x .. c
    return sink
end
foo("a", "b", "c")
foo("a", "b", "c")
foo("a", "b", "c")
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1', '-narrow')",
        ins = {
            {type = "p32", name = "BUFHDR",
                right_op = op_type.new("lit", "RESET")},
            {type = "p32", name = "BUFPUT"},
            {type = "p32", name = "BUFPUT"},
            {type = "p32", name = "BUFHDR",
                right_op = op_type.new("lit", "APPEND")},
            {type = "p32", name = "BUFPUT"},
            {type = "str", name = "BUFSTR"},
        },
    }, {
        code = [[
-- SLOAD cdt
local function foo(x)
    return x + 1LL
end
foo(5LL)
foo(5LL)
foo(5LL)
]],
        ins = {
            {type = "cdt", name = "SLOAD"},
        },
    }, {
        code = [[
-- XLOAD via FFI int* dereference. Caller hot-calls f, which
-- reads p[0] from raw cdata memory.
local ffi = require('ffi')
local arr = ffi.new("int[1]", 42)
local function f(p) return p[0] + 1 end
local s = 0
s = s + f(arr)
s = s + f(arr)
s = s + f(arr)
]],
        ins = {
            {type = "cdt", name = "SLOAD"},
            {type = "int", name = "XLOAD"},
        },
    }, {
        code = [[
-- XSTORE then XLOAD on same cell: write v to p[0], read back.
-- Forwarding through the xmem array gives v.
local ffi = require('ffi')
local arr = ffi.new("int[1]", 0)
local function f(p, v) p[0] = v; return p[0] end
local s = 0
s = s + f(arr, 1)
s = s + f(arr, 2)
s = s + f(arr, 3)
]],
        ins = {
            {type = "cdt", name = "SLOAD"},
            {type = "int", name = "XSTORE"},
            {type = "int", name = "XLOAD"},
        },
    }, {
        code = [==[
local ffi = require('ffi')
ffi.cdef[[ int abs(int); ]]
local C = ffi.C
local function f(i) C.abs(-i) end
f(1)
f(2)
f(3)
]==],
        ins = {
            {type = "int", name = "CALLXS"},
        },
    }, {
        -- CALLXS i64: external C call returning int64_t
        -- exercises the IRNodeCALLXSI64 variant (UF over the
        -- i64 argument bitvector). The result is stored into
        -- an int64_t cell so it reaches the memory part of the
        -- equivalence check: a wrong result-side translation
        -- would break UF congruence and show up as sat.
        code = [==[
local ffi = require('ffi')
ffi.cdef[[ int64_t llabs(int64_t); ]]
local C = ffi.C
local o = ffi.new("int64_t[1]", 0)
-- The destination cell is passed as an argument: as an upvalue
-- its address would be baked into the trace as a constant cdata
-- pointer, which the i64 binop translation does not accept.
local function f(i, out) out[0] = C.llabs(-i * 1LL) end
f(1, o)
f(2, o)
f(3, o)
]==],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "i64", name = "CALLXS"},
            {type = "i64", name = "XSTORE"},
        },
    }, {
        code = [[
-- XLOAD i64 + XSTORE i64: read an int64_t* cell, store the
-- result into another. Discarded into a cdata cell (not a Lua
-- number) so there is no FP roundtrip.
local ffi = require('ffi')
local src = ffi.new("int64_t[1]", 9000000000LL)
local dst = ffi.new("int64_t[1]", 0)
local function f(p, o) o[0] = p[0] + 1 end
f(src, dst)
f(src, dst)
f(src, dst)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "i64", name = "XLOAD"},
            {type = "i64", name = "XSTORE"},
        },
    }, {
        code = [[
-- XLOAD num + XSTORE num: read a double* cell, store the result
-- into another (mirrors the i64 pair above). Reading a different
-- cell than the store keeps the XLOAD real at opt 3 — a same-cell
-- read-back would be forwarded away.
local ffi = require('ffi')
local src = ffi.new("double[1]", 3.5)
local dst = ffi.new("double[1]", 0)
local function f(p, o) o[0] = p[0] + 1 end
f(src, dst)
f(src, dst)
f(src, dst)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "num", name = "XLOAD"},
            {type = "num", name = "XSTORE"},
        },
    }, {
        code = [==[
-- ADD p64 + MUL i64: indexing p[i] on a non-power-of-2 struct
-- stride (i*12) needs an explicit index multiply, not a shift.
local ffi = require('ffi')
ffi.cdef[[ typedef struct { int a, b, c; } tri; ]]
local arr = ffi.new("tri[4]")
local function f(p, i) arr[i].a = i; return p[i].a end
local s = 0
s = s + f(arr, 0)
s = s + f(arr, 1)
s = s + f(arr, 2)
]==],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "i64", name = "MUL"},
            {type = "p64", name = "ADD"},
        },
    }, {
        code = [[
-- u32 XLOAD / XSTORE and num<->u32 CONV: read two uint32_t array
-- cells, multiply (as num via __index), cast back to u32, store.
-- The factors are picked so that their product exceeds 2^32: the
-- cast back to u32 has to wrap, which is exactly what the u32
-- model must reproduce.
local ffi = require("ffi")
local a = ffi.new("uint32_t[3]", 1000003, 99991, 0)
local function f(p) p[2] = ffi.cast("uint32_t", p[0] * p[1]) end
f(a)
f(a)
f(a)
]],
        ins = {
            {type = "u32", name = "XLOAD"},
            {type = "num", name = "CONV"},
            {type = "u32", name = "CONV"},
            {type = "u32", name = "XSTORE"},
        },
    }, {
        name="u32 MUL",
        code = [[
-- u32 MUL: the narrowing fold turns CONV(u32, i64-MUL) into a
-- wrapped u32 `bvmul`. The result is stored into a uint32_t array
-- (rather than kept as a boxed cdata) so the snapshot avoids an
-- FP<->BV roundtrip and the nonlinear-bitvector query stays
-- tractable for z3. The factors multiply out past 2^32, so the
-- cast back to u32 wraps.
local ffi = require("ffi")
local a = ffi.new("uint32_t", 1000003)
local b = ffi.new("uint32_t", 99991)
local o = ffi.new("uint32_t[1]", 0)
local function f(x, y, out) out[0] = ffi.cast("uint32_t", x * y) end
f(a, b, o)
f(a, b, o)
f(a, b, o)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "CONV",
                right_op = op_type.new("lit", "u32.int")},
            {type = "u32", name = "MUL"},
        },
    }, {
        code = [[
-- u32 NE: equality test on uint32_t cdata lowers to a u32 guard.
local ffi = require("ffi")
local a = ffi.new("uint32_t", 3)
local b = ffi.new("uint32_t", 5)
local o = ffi.new("uint32_t[1]", 0)
local function f(x, y, out) if x == y then out[0] = x else out[0] = y end end
f(a, b, o)
f(a, b, o)
f(a, b, o)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "NE"},
        },
    }, {
        code = [[
-- ASTORE str
local function foo(t)
    t[1] = "hello"
    return t
end
foo({nil})
foo({nil})
foo({nil})
]],
        ins = {
            {type = "str", name = "ASTORE"},
        },
    }, {
        code = [[
-- ASTORE tab
local function foo(t, v)
    t[1] = v
    return t
end
foo({nil}, {})
foo({nil}, {})
foo({nil}, {})
]],
        ins = {
            {type = "tab", name = "ASTORE"},
        },
    }, {
        name = "write nil to array",
        code = [[
-- ASTORE nil: writing nil deletes the array slot. Without
-- the nil-ASTORE handler this lands on the dummy path and
-- the downstream ALOAD guard sats spuriously.
local function foo(t)
    t[1] = nil
    return t[1]
end
foo({1})
foo({1})
foo({1})
]],
        ins = {
            {type = "nil", name = "ASTORE"},
        },
    }, {
        code = [[
local x = {}
for i = 1, 3 do
  x = { [-0.000000] = "123" }

end

assert(x[0.0] == "123")
]],
        ins = {
            {type = "num", name = "CONV"},
            {type = "num", name = "NEG"},
            {type = "p32", name = "NEWREF"},
            {type = "str", name = "HSTORE"},
        },
    }, {
        code = [[
-- SLOAD tru/fal test: boolean argument triggers
-- SLOAD with type tru or fal.
local function foo(b, x)
  if b then return x + 1 end
  return x
end
foo(true, 1.0)
foo(true, 2.0)
foo(true, 3.0)
]],
        ins = {
            {type = "tru", name = "SLOAD"},
        },
    }, {
        code = [[
-- SLOAD tru/fal test: boolean argument triggers
-- SLOAD with type tru or fal.
local function foo(b, x)
  if b then return x + 1 end
  return x
end
foo(false, 1.0)
foo(false, 4.0)
foo(false, 5.0)
]],
        ins = {
            {type = "fal", name = "SLOAD"},
        },
    }, {
        name = "FORL narrowing",
        -- The narrowed opt trace adds *after* converting the
        -- induction variable to int32 while the unopt one
        -- converts after adding in fp, so proving them equal is
        -- an fp <-> bitvector commutation argument repeated per
        -- iteration. z3 discharges it at depth 1 but not at 2.
        unroll_n = 1,
        code = [[
-- FORL narrowing: IV becomes int SLOAD with CI guard,
-- step becomes int ADD, and the array write goes through
-- CONV num.int to widen back to a num cell.
local function foo()
    local t = {}
    for i = 1, 50 do t[i] = i end
    return t[10]
end
foo()
foo()
foo()
]],
        ins = {
            -- Instructions are checked against the unopt trace
            -- (level 0). The narrowed opt trace turns SLOAD into
            -- int+CI and ADD into int; the equivalence check
            -- (traces_to_smt) verifies both.
            {type = "num", name = "SLOAD"},
            {type = "int", name = "CONV"},
            {type = "num", name = "ADD"},
        },
    }, {
        code = [[
-- CALLN test: math.* with constant argument.
local function foo()
  local x = 0.1
  return math.acos(x),
         math.asin(x),
         math.atan(x),
         math.cos(x),
         math.cosh(x),
         math.exp(x),
         math.log(x),
         math.log10(x),
         math.sin(x),
         math.sinh(x),
         math.tan(x),
         math.tanh(x)
end
foo(1)
foo(1)
foo(1)
foo(1)
foo(1)
]],
        ins = {
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "acos")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "asin")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "atan")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "cos")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "cosh")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "exp")},
            {type = "num", name = "FPMATH"}, -- log
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "log10")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "sin")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "sinh")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "tan")},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "tanh")},
        },
    }, {
        code = [[
x = {}
for i = 0, 100 do
    local x = string.reverse("ASD")
    res = #x
end
]],
        ins = {
            {type = "p32", name = "CALLL"},
            {type = "str", name = "BUFSTR"},
            {type = "int", name = "FLOAD"},
        },
    }, {
        code = [[
-- Constant folding of table read after write.
local sin = math.sin
local res = 0.0
local x = {}
for i = 0, 100 do
    x["z"] = 0.42
    x[0.42] = "z"
    res = res + sin(x["z"])
    res = res + #(x[0.42])
end
]],
        ins = {
            {type = "p32", name = "HREFK"},
            {type = "num", name = "HSTORE"},
            {type = "num", name = "HLOAD"},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "sin")},
        },
    }, {
        code = [[
-- Constant folding of table read after write through HREF.
-- HREF (not HREFK) requires the key's hash to fall outside LJ's
-- node-array fold range. table.new(0, N) with N large pushes
-- hmask high enough that "mykey" doesn't fit. Brittle if LJ
-- changes the hash function or fold threshold.
local sin = math.sin
local res = 0.0
local t = require('table.new')(0, 1.4e5)
for _ = 1, 100 do
    t["mykey"] = 0.42
    res = res + sin(t["mykey"])
end
]],
        ins = {
            {type = "p32", name = "HREF",
                right_op = op_type.new("string", "mykey")},
            {type = "num", name = "HSTORE"},
            {type = "num", name = "HLOAD"},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "sin")},
        },
    }, {
        code = [[
local sin = math.sin
local res = 0.0
for i = 0, 100 do
    local x = {}
    x["k"] = 0.42
    res = res + sin(x["k"])
end
]],
        ins = {
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
        },
    }, {
        -- Not unrolled. The string reaches str.len through an
        -- op-stack slot rather than as a literal, so each
        -- iteration makes the solver reason about the length of
        -- an unconstrained string, convert it with int2bv, and
        -- feed that to an uninterpreted sin. Even one body copy
        -- costs z3 97s and defeats cvc5 entirely; one iteration
        -- already covers the FLOAD being checked.
        unroll_n = 0,
        code = [[
local sin = math.sin
local res = 0.0
local s = "hello"
for i = 1, 100 do
    res = res + sin(#s)
end
]],
        ins = {
            {type = "int", name = "FLOAD"},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "sin")},
        },
    }, {
        name = "string const through HSTORE/HLOAD/str.len",
        -- Without const_strs forwarding, the
        -- opt trace folds #(t.k) to a literal while unopt keeps a
        -- symbolic str.len, so the equiv check sats spuriously.
        code = [[
local t = {}
local res = 0
for i = 1, 30 do
    t.k = "hello"
    res = #(t.k)
end
]],
        ins = {
            {type = "str", name = "HSTORE"},
            {type = "str", name = "HLOAD"},
            {type = "int", name = "FLOAD",
                right_op = op_type.new("lit", "str.len")},
        },
    }, {
        code = [[
-- Store inner table, load it back, store a number into it.
local function foo()
    local outer = {}
    local inner = {}
    inner["a"] = 1
    outer["t"] = inner
    return outer
end
foo()
foo()
foo()
]],
        ins = {
            {type = "tab", name = "TNEW"},
            {type = "tab", name = "TNEW"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "tab", name = "HSTORE"},
        },
    }, {
        code = [[
-- Load inner table and access its field.
local function foo()
    local outer = {}
    outer["inner"] = {}
    local t = outer["inner"]
    t["x"] = 42
    return t["x"]
end
foo()
foo()
foo()
]],
        ins = {
            {type = "tab", name = "TNEW"},
            {type = "tab", name = "TNEW"},
            {type = "p32", name = "NEWREF"},
            {type = "tab", name = "HSTORE"},
            {type = "p32", name = "HREFK"},
            {type = "tab", name = "HLOAD"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "HREFK"},
            {type = "num", name = "HLOAD"},
        },
    }, {
        code = [[
-- Two levels of nesting.
local function foo()
    local a = {}
    local b = {}
    local c = {}
    c["v"] = 10
    b["c"] = c
    a["b"] = b
    return a
end
foo()
foo()
foo()
]],
        ins = {
            {type = "tab", name = "TNEW"},
            {type = "tab", name = "TNEW"},
            {type = "tab", name = "TNEW"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "tab", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "tab", name = "HSTORE"},
        },
    }, {
        code=[[
local t = {1.0}
for i = 1, 1000 do
    if i > 1 then
        local s = t[1]
        return s
    end
end
]],
        ins = {
            {type = "tab", name = "SLOAD"},
            {type = "num", name = "ALOAD"},
        },
    }, {
        code = [[
-- Store two different inner tables.
local function foo()
    local outer = {}
    local t1 = {}
    local t2 = {}
    t1["x"] = 1
    t2["x"] = 2
    outer["a"] = t1
    outer["b"] = t2
    return outer
end
foo()
foo()
foo()
]],
        ins = {
            {type = "tab", name = "TNEW"},
            {type = "tab", name = "TNEW"},
            {type = "tab", name = "TNEW"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "num", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "tab", name = "HSTORE"},
            {type = "p32", name = "NEWREF"},
            {type = "tab", name = "HSTORE"},
        },
    }, {
        name = "write to global variable",
        code = [[
function m()
  v = 1
  return v
end

m()
m()
m()
m()
]],
        ins = {
            {type = "fun", name = "SLOAD"},
            {type = "tab", name = "FLOAD",
                right_op = op_type.new("lit", "func.env")
            },
        },
    }, {
        name = "read string global variable",
        code = [[
function m()
  v = "hello"
  return v
end

m()
m()
m()
m()
]],
        ins = {
            {type = "fun", name = "SLOAD"},
            {type = "tab", name = "FLOAD",
                right_op = op_type.new("lit", "func.env")
            },
            {type = "str", name = "HLOAD"},
        },
    }, {
        name = "read nested global through math",
        code = [[
local function m()
  local x = math.pi
  return x + 1
end

m()
m()
m()
m()
]],
        ins = {
            {type = "fun", name = "SLOAD"},
            {type = "tab", name = "FLOAD",
                right_op = op_type.new("lit", "func.env")
            },
        },
    }, {
        name = "read field through metatable __index",
        code = [[
local mt = {__index = {x = 42}}
local t = setmetatable({}, mt)
local r = 0
for i = 1, 30 do
    r = r + t.x
end
]],
        ins = {
            {type = "tab", name = "FLOAD",
                right_op = op_type.new("lit", "tab.meta")
            },
        },
    }, {
        name = "write bool + DSE",
        code = [[
local t = {}
local other = {}
for i = 1, 30 do
    t.k = other
    -- Previous write will be DSEd, and if HSTORE for bool is not
    -- implemented formula will give SAT.
    t.k = false
end
]],
        ins = {
            {type = "tab", name = "HSTORE"},
            {type = "fal", name = "HSTORE"},
        },
    }, {
        name = "POW with constant base",
        code = [[
local x = 1.0
local r = 0.0
for i = 1, 30 do
    r = 3.0 ^ x
end
]],
        ins = {
            {type = "num", name = "POW"},
        },
    }, {
        -- POW with both operands symbolic (no const fold). Tests
        -- the uninterpreted pow_fp path: deterministic axiom-free
        -- semantics, both traces produce same symbolic result.
        name = "POW symbolic base and exponent",
        code = [[
local function f(b, e)
    return b ^ e
end
f(2.0, 3.0)
f(2.0, 3.0)
f(2.0, 3.0)
f(2.0, 3.0)
]],
        ins = {
            {type = "num", name = "POW"},
        },
    }, {
        -- 1 ^ x: identity fold target. const_nums propagation
        -- should yield 1.0 regardless of x.
        name = "POW 1 ^ x",
        code = [[
local x = 2.0
local r = 0.0
for i = 1, 30 do
    r = 1.0 ^ x
end
]],
        ins = {
            {type = "num", name = "POW"},
        },
    }, {
        -- 1 ^ 1 via runtime-bound locals so LuaJIT can't
        -- compile-time fold the operand pair. Const-fold axiom
        -- pins pow_fp(1, 1) = 1; both traces agree.
        name = "POW 1 ^ 1",
        code = [[
local f = function(x)
    local b = 1.0
    return b ^ b + x
end
f(1)
f(2)
f(3)
f(4)
]],
        ins = {
            {type = "num", name = "POW"},
        },
    }, {
        -- Regression: STRTO with literal string must populate
        -- ctx.const_nums so the const value propagates through
        -- the arithmetic chain into CALLN, which then emits the
        -- pinning axiom `(= (math_fn const) folded_const)`.
        -- Without the axiom math_fn stays uninterpreted and the
        -- optimized trace (which FOLDed the call to a literal)
        -- cannot be proved equivalent => spurious sat.
        code = [[
local r = 0
for i = 1, 30 do
    r = math.cos(tonumber("0.5"))
end
]],
        ins = {
            {type = "num", name = "STRTO"},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "cos")},
        },
    }, {
        -- Two SLOADs of the same env table (one for the
        -- global HSTORE, one inside the loop body to call
        -- math.tan) create independent const_tabs entries.
        -- The HSTORE writes 42 into const_tabs[t1].content
        -- but the HLOAD reads from const_tabs[t2].content
        -- (empty), so `tan` arg never resolves to a const,
        -- no `(= (math_tan 42.0) <result>)` axiom emitted,
        -- and the opt trace's FOLD-baked constant diverges
        -- from unopt's symbolic `math_tan(HLOAD)` -> sat.
        name = "double-SLOAD same env, HSTORE then CALLN tan",
        code = [[
v = 0
local r = 0
for i = 1, 30 do
    v = 42
    r = r + math.tan(v)
end
]],
        ins = {
            {type = "num", name = "HSTORE"},
            {type = "num", name = "HLOAD"},
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "tan")},
        },
    }, {
        name = "LDEXP with constant operands",
        code = [[
local r = 0.0
for i = 1, 30 do
    r = math.ldexp(3.0, 4.0)
end
]],
        ins = {
            {type = "num", name = "LDEXP"},
        },
    }, {
        -- LDEXP identity fold: ldexp(x, 0) = x. Mirrors POW's
        -- x^1 fold so const_nums propagation survives.
        name = "LDEXP identity (exponent 0)",
        code = [[
local r = 0.0
for i = 1, 30 do
    r = math.ldexp(2.5, 0)
end
]],
        ins = {
            {type = "num", name = "LDEXP"},
        },
    }, {
        name = "CALLN atan2 with constant operands",
        code = [[
local r = 0.0
for i = 1, 30 do
    r = math.atan2(3.0, 4.0)
end
]],
        ins = {
            {type = "num", name = "CALLN",
                right_op = op_type.new("lit", "atan2")},
        },
    }, {
        code = [[
local ffi = require("ffi")
local a = ffi.new("uint32_t", 4294967290)
local b = ffi.new("uint32_t", 7)
local o = ffi.new("uint32_t[1]", 0)
local function f(x, y, out) out[0] = ffi.cast("uint32_t", x + y) end
f(a, b, o)
f(a, b, o)
f(a, b, o)
]],
        -- u32 ops only appear after narrowing (opt level 3).
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "FLOAD"},
            {type = "u32", name = "ADD"},
        },
    }, {
        code = [[
local ffi = require("ffi")
local a = ffi.new("uint32_t", 3)
local b = ffi.new("uint32_t", 7)
local o = ffi.new("uint32_t[1]", 0)
local function f(x, y, out) out[0] = ffi.cast("uint32_t", x - y) end
f(a, b, o)
f(a, b, o)
f(a, b, o)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "SUB"},
        },
    }, {
        code = [[
-- u32 NE: `~=` on uint32_t cdata lowers to a u32 inequality guard.
-- The branch result is a plain number (not a boxed u32 cdata), so
-- there is no FP<->BV roundtrip and z3 stays tractable.
local ffi = require("ffi")
local a = ffi.new("uint32_t", 3)
local b = ffi.new("uint32_t", 5)
local s = 0
local function f(x, y) if x ~= y then s = s + 1 else s = s + 2 end end
f(a, b)
f(a, b)
f(a, b)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "NE"},
        },
    }, {
        code = [[
-- u32 EQ: `~=` on equal uint32_t cdata takes the false branch, so
-- the guard emitted is an equality one. As in the NE test above,
-- the branch result is a plain number, so there is no FP<->BV
-- roundtrip and z3 stays tractable.
local ffi = require("ffi")
local a = ffi.new("uint32_t", 3)
local b = ffi.new("uint32_t", 3)
local s = 0
local function f(x, y) if x ~= y then s = s + 1 else s = s + 2 end end
f(a, b)
f(a, b)
f(a, b)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "EQ"},
        },
    }, {
        code = [[
-- CONV num->u32 (and u32->num): cast a double to uint32_t, then
-- read it back via tonumber. Both directions are converted back
-- to a plain num for accumulation, so no boxed cdata roundtrip.
local ffi = require("ffi")
local o = ffi.new("double[1]", 0)
local function f(x, out) out[0] = tonumber(ffi.cast("uint32_t", x * 1.5)) end
f(1, o)
f(2, o)
f(3, o)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "CONV",
                right_op = op_type.new("lit", "u32.num none")},
            {type = "num", name = "CONV",
                right_op = op_type.new("lit", "num.u32")},
        },
    }, {
        code = [[
-- CONV u32->num: use a uint32_t cdata in floating-point arithmetic
-- via tonumber, forcing an unsigned-to-float conversion.
local ffi = require("ffi")
local k = ffi.new("uint32_t", 7)
local o = ffi.new("double[1]", 0)
local function f(x, out) out[0] = tonumber(x) * 1.5 end
f(k, o)
f(k, o)
f(k, o)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "num", name = "CONV",
                right_op = op_type.new("lit", "num.u32")},
        },
    }, {
        code = [[
local ffi = require("ffi")
local a = ffi.new("uint32_t", 1000003)
local b = ffi.new("uint32_t", 99991)
local o = ffi.new("uint32_t[1]", 0)
local function f(x, y, out) out[0] = ffi.cast("uint32_t", x * y) end
f(a, b, o)
f(a, b, o)
f(a, b, o)
]],
        ins = {
            {type = "i64", name = "CONV",
                right_op = op_type.new("lit", "i64.int")},
            {type = "u32", name = "CONV",
                right_op = op_type.new("lit", "u32.i64")},
        },
    }, {
        name = "u32 UGT (<)",
        code = [[
local ffi = require("ffi")
local a = ffi.new("uint32_t", 3)
local b = ffi.new("uint32_t", 5)
local s = 0
local function f(x, y) if x < y then s = s + 1 else s = s + 2 end end
f(a, b)
f(a, b)
f(a, b)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "UGT"},
        },
    }, {
        name = "u32 UGE (<=)",
        code = [[
local ffi = require("ffi")
local a = ffi.new("uint32_t", 3)
local b = ffi.new("uint32_t", 5)
local s = 0
local function f(x, y) if x <= y then s = s + 1 else s = s + 2 end end
f(a, b)
f(a, b)
f(a, b)
f(a, b)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "UGE"},
        },
    }, {
        name = "u32 ULE (>)",
        code = [[
local ffi = require("ffi")
local a = ffi.new("uint32_t", 3)
local b = ffi.new("uint32_t", 5)
local s = 0
local function f(x, y) if x > y then s = s + 1 else s = s + 2 end end
f(a, b)
f(a, b)
f(a, b)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "ULE"},
        },
    }, {
        name = "u32 ULT (>=)",
        code = [[
local ffi = require("ffi")
local a = ffi.new("uint32_t", 3)
local b = ffi.new("uint32_t", 5)
local s = 0
local function f(x, y) if x >= y then s = s + 1 else s = s + 2 end end
f(a, b)
f(a, b)
f(a, b)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "ULT"},
        },
    }, {
        name = "CONV i64->u32 truncation",
        code = [[
local ffi = require("ffi")
local x = ffi.new("int64_t", 123456789012345)
local o = ffi.new("double[1]", 0)
local function f(v, i, out) out[0] = tonumber(ffi.cast("uint32_t", v + i)) end
f(x, 1, o)
f(x, 2, o)
f(x, 3, o)
]],
        opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
        ins = {
            {type = "u32", name = "CONV",
                right_op = op_type.new("lit", "u32.i64")},
            {type = "u32", name = "ADD"},
            {type = "num", name = "CONV",
                right_op = op_type.new("lit", "num.u32")},
        },
    }, {
        name = "XSTORE/XLOAD flt",
        code = [[
-- Write a double into an FFI float cell and read it back. Both
-- directions go through float32, so 1e39 -- finite as a double,
-- past the float32 maximum -- has to come back as inf.
local ffi = require('ffi')
local arr = ffi.new("float[1]", 0)
local function f(p, v) p[0] = v; return p[0] end
local s = 0
s = s + f(arr, 1e39)
s = s + f(arr, 1e39)
s = s + f(arr, 1e39)
]],
        ins = {
            {type = "flt", name = "CONV"},
            {type = "flt", name = "XSTORE"},
            {type = "flt", name = "XLOAD"},
            {type = "num", name = "CONV"},
        },
    }, {
        -- An array read is an ABC against the table's own size,
        -- so the size load has to survive as well -- both are
        -- dropped as NYI if either one is. Integer keys also
        -- grow the array part, so the sizes here are the
        -- rehashed ones.
        name = "ABC against the table's own size",
        code = [[
local function foo(x)
    x[1] = 1
    x[2] = 2
    x[3] = 3
    return x[1] + x[3]
end

foo({})
foo({})
foo({})
]],
        ins = {
            {type = "p32", name = "NEWREF"},
            {type = "int", name = "FLOAD"},
            {type = "int", name = "ABC"},
            {type = "num", name = "ALOAD"},
        },
    }, {
        -- `dead` is allocated at -O0 and gone at -O3, so the two
        -- traces allocate a different number of tables; the one
        -- that escapes into `dst` has to be recognized as the
        -- same table anyway. Reads sat if local tables are
        -- matched by allocation order instead of by escape.
        -- An upvalue still open -- the chunk that owns it is
        -- running -- is named by UREFO rather than UREFC. It was
        -- NYI, so the body of any closure writing a file-scope
        -- local went missing.
        name = "open upvalue read and written",
        code = [[
local up = 0
local function foo(i)
    up = i
    return up + 1
end

foo(1)
foo(2)
foo(3)
]],
        ins = {
            {type = "p32", name = "UREFO"},
            {type = "num", name = "USTORE"},
            {type = "num", name = "ULOAD"},
        },
    }, {
        -- A closure counting in an upvalue: UREFC names the
        -- upvalue, ULOAD/USTORE read and write it. All four were
        -- NYI, so the whole closure body vanished from the
        -- formula.
        name = "closed upvalue read and written",
        code = [[
local function mk()
    local n = 0
    return function() n = n + 1 return n end
end
local f = mk()
f() f() f() f() f()
]],
        ins = {
            {type = "p32", name = "UREFC"},
            {type = "num", name = "ULOAD"},
            {type = "num", name = "USTORE"},
        },
    }, {
        -- setmetatable() lowers to FREF + FSTORE. FSTORE was
        -- implemented but its FREF operand was not, so the
        -- transitive NYI poisoning dropped every field store
        -- from the formula.
        name = "metatable stored through an FREF",
        code = [[
local function foo(t, m)
    setmetatable(t, m)
    return t
end

local mt = {}
foo({}, mt)
foo({}, mt)
foo({}, mt)
]],
        ins = {
            {type = "p32", name = "FREF"},
            {type = "tab", name = "FSTORE"},
            {type = "tab", name = "TBAR"},
        },
    }, {
        name = "local table matched across a dropped allocation",
        code = [[
local function fill(dst)
    for _ = 1, 6 do
        local dead = {}
        dst.x = {}
    end
end

local d = {}
fill(d)
fill(d)
fill(d)
]],
        unroll_n = 2,
        ins = {
            {type = "tab", name = "TNEW"},
            {type = "tab", name = "HSTORE"},
        },
    }}
    test:plan(3 * #srcs)

    local unroll_n = ljopt_config.get_loop_unroll_count()
    for i, f in ipairs(srcs) do
        local label = f.name or ("test_%d"):format(i)
        -- Depth is per-test: a chunk may only stay decidable
        -- below the global setting. See set_loop_unroll_count.
        ljopt_config.set_loop_unroll_count(f.unroll_n or unroll_n)
        local ok, err = check_ins_present(f.code, f.ins, f.opt)
        test:ok(ok, ("%s instructions present: %s"):format(
            label, err or "ok"
        ))
        local formulas = ljopt.ir.traces_to_smt(f.code)
        for j, formula in pairs(formulas) do
            formula = smt_constants.LJOPT_SMTLIB .. formula
            test:is(smt:parse(formula), true,
                ("%s trace %s parse."):format(label, j))
            test:is(smt:check(formula), smt.result.UNSAT,
                ("%s trace %s check."):format(label, j))
        end
    end
    ljopt_config.set_loop_unroll_count(unroll_n)
    -- Restore strict mode.
    ljopt_config.set_strict_mode(strict_mode)
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
