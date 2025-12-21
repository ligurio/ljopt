-- This test file contains tests related to
-- single snapshot instruction.
-- In general test should look like:
-- We translate single instruction with some input.
-- We already know the expected result, so we just
-- compare in SMT, that result of this instruction
-- is same as expected result.
--
-- Example:
--
-- ADD 1 2
-- In SMT will look like
-- (assert (let ((a!1 (bvand (bvadd #x0000000000000001
--          #x0000000000000002) #x00000000ffffffff)))
--
-- But we already know it should be 3, so we add
-- assertion and check whether formula is SAT.

local smt = require("tests.smtlib2").new()
local test = require("tests.tap").test("ljopt")

local translate = require("ljopt.ir_smtlib")
local smt_context = require("ljopt.ir.smt_context")
local ffi = require("ffi")
local bit = require("bit")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

test:plan(3)

-- Get float in SMT format.
local function f2bv(x)
  local u = ffi.new("union { double d; uint64_t i; }")
  u.d = x
  local bits = u.i
  local hi = tonumber(bit.rshift(bits, 32))
  local lo = tonumber(bit.band(bits, 0xFFFFFFFF))
  return string.format("#x%08X%08X", hi, lo)
end

local function create_node(irtype, irop, op1, op2, insn)
    insn = insn or 1
    local node = {
        num = insn,
        flags = "",
        irt_guard = nil,
        irt_isphi = nil,
        irtype = irtype,
        irop = irop,
        op1 = op1,
        op2 = op2,
    }
    return node
end

test:test("IR arithmetic tests", function(test)

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = ctx_src.op_stack:init_smt("op")

    local op_id = 1

    local nodes_to_test = {
        {node = create_node("num", "ADD", f2bv(2.3), f2bv(3.4)),
                        result = 2.3 + 3.4, error = 1.},
        {node = create_node("int", "ADD", f2bv(2.), f2bv(3.0)),
                        result = 5, error = 1.},
        {node = create_node("int", "ADDOV", f2bv(2.3), f2bv(3.4)),
                        result = 5, error = 1.},
        {node = create_node("int", "BAND", f2bv(124245235.), f2bv(824124435.)),
                        result = bit.band(124245235, 824124435), error = 1.},
        {node = create_node("int", "BNOT", f2bv(124245235)),
                            result = bit.bnot(124245235), error = 1.},
        {node = create_node("int", "BOR", f2bv(124245235), f2bv(824124435)),
                            result = bit.bor(124245235, 824124435), error = 1.},
        {node = create_node("int", "BSAR", f2bv(124245235), f2bv(2)),
                            result = bit.rshift(124245235, 2), error = 1.},
        {node = create_node("int", "BSHL", f2bv(124245235), f2bv(2)),
                            result = bit.lshift(124245235, 2), error = 1.},
        {node = create_node("int", "BSHR", f2bv(124245235), f2bv(2)),
                            result = bit.rshift(124245235, 2), error = 1.},
        {node = create_node("int", "BXOR", f2bv(124245235), f2bv(2)),
                            result = bit.bxor(124245235, 2), error = 1.},
        {node = create_node("num", "CONV", f2bv(3.0), "num.int"),
                        result = 3, error = 2},
        {node = create_node("num", "DIV", f2bv(2.3), f2bv(3.4)),
                        result = 2.3 / 3.4, error = 1.},
        {node = create_node("int", "DIV", f2bv(23.), f2bv(4.)),
                        result = 5, error = 1.},
        {node = create_node("int", "MOD", f2bv(5), f2bv(3)),
                        result = math.fmod(5, 3), error = 1},
        {node = create_node("num", "MUL", f2bv(2.3), f2bv(3.4)),
                        result = 2.3 * 3.4, error = 1.},
        {node = create_node("int", "MUL", f2bv(2.), f2bv(3.)),
                        result = 2 * 3, error = 1.},
        {node = create_node("num", "NEG", f2bv(2.3), nil),
                        result = -2.3, error = 1.},
        {node = create_node("int", "NEG", f2bv(2.), nil),
                        result = -2, error = 1.},
        {node = create_node("num", "SUB", f2bv(2.3), f2bv(3.4)),
                        result = 2.3 - 3.4, error = 1.},
        {node = create_node("int", "SUB", f2bv(2.), f2bv(4.)),
                        result = 2 - 4, error = 1.},
    }
    test:plan(3 * #nodes_to_test)
    -- Test each node in a loop.
    for _i, test_case in ipairs(nodes_to_test) do
        local res = op_init .. "\n" .. translate.translate(
            { trace = { test_case.node } }, ctx_src, nil, nil
        )

        -- Test SMT-LIB parsing
        test:is(smt:parse(res), true,
            "SMT-LIB parsing for test case " .. test_case.node.irop
        )

        -- Create assertion based on the operation type
        -- and expected result
        local expected = ""
        local unexpected = ""
        if test_case.node.irtype == "num" then
            expected = " ((_ to_fp 11 53) " .. f2bv(test_case.result) .. ")"
            unexpected = " ((_ to_fp 11 53) " .. f2bv(test_case.error) .. ")"
        elseif test_case.node.irtype == "i64" then
            expected = string.format("#x%.16x", test_case.result)
            unexpected = string.format("#x%.16x", test_case.error)
        elseif test_case.node.irtype == "i32" or
               test_case.node.irtype == "int" then
            -- To not convert op_stack from 64 bytes to 32 and
			-- back - just use 64 here.
            expected = string.format("#x%.8x%s", 0,
                bit.tohex(bit.band(test_case.result, 0xFFFFFFFF), 8))
            unexpected = string.format("#x%.8x%s", 0,
                bit.tohex(bit.band(test_case.error, 0xFFFFFFFF), 8))
        else
            assert(false, "Unsupported " .. test_case.node.irtype)
        end
        local expect_sat = res .. "\n(assert (= " ..
		    ctx_src.op_stack:load(op_id, test_case.node.irtype)
        expect_sat = expect_sat .. expected .. "))"
        test:is(smt:check(expect_sat), smt.result.SAT,
            "SMT-LIB checking SAT " .. test_case.node.irop
        )

        local expect_unsat = res .. "\n(assert (= " ..
		    ctx_src.op_stack:load(op_id, test_case.node.irtype)
        expect_unsat = expect_unsat .. unexpected .. "))"
        test:is(smt:check(expect_unsat), smt.result.UNSAT,
            "SMT-LIB checking UNSAT " .. test_case.node.irop
        )

    end
end)

test:test("IR guards tests", function(test)

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = ctx_src.op_stack:init_smt("op")

    local op_id = 1

    local nodes_to_test = {
        {node = create_node("int", "ADDOV", f2bv(2.), f2bv(3.0)),
                        result = "true", error = "false"},
        {node = create_node("int", "ADDOV",
                        f2bv(2147483647), f2bv(2147483647)),
                        result = "false", error = "true"},
        {node = create_node("int", "EQ", f2bv(23.), f2bv(23.)),
		                    result = true, error = false, te=true},
        {node = create_node("num", "EQ", f2bv(2), f2bv(2)),
                        result = "true", error = "false"},
        {node = create_node("num", "EQ", f2bv(2), f2bv(2.5)),
                        result = "false", error = "true"},
        {node = create_node("int", "GE", f2bv(23.), f2bv(4.)),
		                    result = true, error = false},
        {node = create_node("int", "GT", f2bv(24.), f2bv(23.)),
		                    result = true, error = false},
        {node = create_node("num", "LE", f2bv(2.3), f2bv(3.4)),
                        result = "true", error = "false"},
        {node = create_node("int", "LE", f2bv(23.), f2bv(4.)),
		                    result = false, error = true},
        {node = create_node("int", "LT", f2bv(22.), f2bv(23.)),
		                    result = true, error = false},
        {node = create_node("num", "NE", f2bv(2), f2bv(2)),
                        result = "false", error = "true"},
        {node = create_node("num", "NE", f2bv(2), f2bv(2.5)),
                        result = "true", error = "false"},
        {node = create_node("int", "UGE", f2bv(3), f2bv(3)),
                        result = "true", error = "false"},
        {node = create_node("int", "UGE", f2bv(2), f2bv(3)),
                        result = "false", error = "true"},
        {node = create_node("int", "UGT", f2bv(3), f2bv(2)),
                        result = "true", error = "false"},
        {node = create_node("int", "UGT", f2bv(3), f2bv(3)),
                        result = "false", error = "true"},
        {node = create_node("int", "ULE", f2bv(2), f2bv(2)),
                        result = "true", error = "false"},
        {node = create_node("int", "ULE", f2bv(3), f2bv(2)),
                        result = "false", error = "true"},
        {node = create_node("int", "ULT", f2bv(2), f2bv(3)),
                        result = "true", error = "false"},
        {node = create_node("int", "ULT", f2bv(3), f2bv(3)),
                        result = "false", error = "true"},
    }
    test:plan(3 * #nodes_to_test)
    -- Test each node in a loop.
    for _i, test_case in ipairs(nodes_to_test) do
        local res = op_init .. "\n" .. translate.translate(
            { trace = {test_case.node} }, ctx_src, nil, nil
        )

        -- Test SMT-LIB parsing.
        test:is(smt:parse(res), true,
            "SMT-LIB parsing for test case " .. test_case.node.irop
        )

        -- Create assertion based on the operation type
        -- and expected result.
        local te_value = ctx_src.te_stack:load(op_id)
        local expected = test_case.result
        local unexpected = test_case.error
        local expect_sat = ("%s\n(assert (= %s %s))\n"):format(
            res, te_value, expected
        )
        test:is(smt:check(expect_sat), smt.result.SAT,
            "SMT-LIB checking guard SAT " .. test_case.node.irop
        )

        local expect_unsat = ("%s\n(assert (= %s %s))"):format(
            res, te_value, unexpected
        )
        test:is(smt:check(expect_unsat), smt.result.UNSAT,
            "SMT-LIB checking guard UNSAT " .. test_case.node.irop
        )
    end
end)

test:test("CONV from op", function(test)
    -- 0001 >  int ADDOV  #x4000000000000000  #x4008000000000000
    -- 0002    num CONV   0001  num.int

    test:plan(1)

    local conv_slot = 2
    local addov_node = create_node("int", "ADDOV", f2bv(2), f2bv(3), 1)
    local conv_node = create_node("num", "CONV", "0001", "num.int", conv_slot)

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = ctx_src.op_stack:init_smt("op")

    local conv_smt = translate.translate(
        {trace={addov_node, conv_node}}, ctx_src, nil, nil
    )

    local expect_sat =
        op_init ..
        conv_smt ..
        ("\n(assert (= %s ((_ to_fp 11 53) %s)))"):format(
               ctx_src.op_stack:load(conv_slot, "num"), f2bv(5))
    test:is(smt:check(expect_sat), smt.result.SAT,
        "SMT-LIB checking CONV is SAT"
    )
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
