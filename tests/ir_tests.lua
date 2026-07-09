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
local op_type = require('ljopt.ir.op_type')
local smt_constants = require("ljopt.smt_constants")
local smt_context = require("ljopt.ir.smt_context")
local utils = require("ljopt.utils")

local ffi = require("ffi")
local bit = require("bit")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

test:plan(11)

-- Get float in SMT format.
local function f2bv(x)
  local u = ffi.new("union { double d; uint64_t i; }")
  u.d = x
  local bits = u.i
  local hi = tonumber(bit.rshift(bits, 32))
  local lo = tonumber(bit.band(bits, 0xFFFFFFFF))
  return string.format("#x%08X%08X", hi, lo)
end

local function num(v) return {type = "number", value = v} end
local function imm(v) return {type = "imm", value = v} end
local function ssa(v) return {type = "ssa", value = v} end
local function str(v) return {type = "string", value = v} end
local function i64(v) return {type = "int64", value = v} end

local function create_node(irtype, irop, op1_val, op2_val, insn)
    insn = insn or 1
    local function process_op(val)
        if val == nil then
            return nil
        elseif type(val) == "table" then
            if val.type == "number" then
                return f2bv(val.value)
            elseif val.type == "ssa" then
                return string.format("%04d", val.value)
            elseif val.type == "imm" then
                return string.format("#%d", val.value)
            elseif val.type == "string" then
                return '"' .. val.value .. '"'
            elseif val.type == "int64" then
                return tostring(val.value)
            else
                error("Unknown op type: " .. tostring(val.type))
            end
        elseif type(val) == "string" then
            return val
        else
            error("Unexpected op value type: " .. type(val))
        end
    end
    local op1_txt = process_op(op1_val)
    local op2_txt = process_op(op2_val)
    return {
        num = insn,
        flags = {
            irt_guard = nil,
            irt_isphi = nil,
        },
        irtype = irtype,
        irop = irop,
        op1 = op1_val,
        op1_txt = op1_txt,
        op2 = op2_val,
        op2_txt = op2_txt,
    }
end

test:test("IR arithmetic tests", function(test)

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = smt_constants.LJOPT_SMTLIB ..
        ctx_src.op_stack:init_smt("op")

    local op_id = 1

    local nodes_to_test = {
        {node = create_node("num", "ABS", num(-2.3)),
		                result = 2.3, error = 1.},
        {node = create_node("int", "ABS", num(-2.)),
		                result = 2, error = 1.},
        {node = create_node("num", "ADD", num(2.3), num(3.4)),
                        result = 2.3 + 3.4, error = 1.},
        {node = create_node("int", "ADD", num(2.), num(3.0)),
                        result = 5, error = 1.},
        {node = create_node("int", "ADDOV", num(2.3), num(3.4)),
                        result = 5, error = 1.},
        {node = create_node("int", "BAND", num(124245235.), num(824124435.)),
                        result = bit.band(124245235, 824124435), error = 1.},
        {node = create_node("int", "BNOT", num(124245235)),
                        result = bit.bnot(124245235), error = 1.},
        {node = create_node("int", "BOR", num(124245235), num(824124435)),
                        result = bit.bor(124245235, 824124435), error = 1.},
        {node = create_node("int", "BROL", num(124245235), num(2)),
                        result = bit.rol(124245235, 2), error = 1.},
        {node = create_node("i64", "BROL", num(3.), num(2.)),
                        result = 12, error = 1},
        {node = create_node("i64", "BROL", num(-3.), num(1.)),
                        result = -5, error = 1},
        {node = create_node("int", "BROR", num(124245235), num(2)),
                        result = bit.ror(124245235, 2), error = 1.},
        {node = create_node("i64", "BROR", num(12.), num(2.)),
                        result = 3, error = 1},
        {node = create_node("i64", "BROR", num(-3.), num(1.)),
                        result = -2, error = 1},
        {node = create_node("int", "BSAR", num(124245235), num(2)),
                        result = bit.rshift(124245235, 2), error = 1.},
        {node = create_node("int", "BSHL", num(124245235), num(2)),
                        result = bit.lshift(124245235, 2), error = 1.},
        {node = create_node("int", "BSHR", num(124245235), num(2)),
                        result = bit.rshift(124245235, 2), error = 1.},
        {node = create_node("int", "BSWAP", num(124245235)),
                        result = bit.bswap(124245235), error = 1.},
        {node = create_node("int", "BXOR", num(124245235), num(2)),
                        result = bit.bxor(124245235, 2), error = 1.},
        {node = create_node("num", "CONV", num(3.0), "num.int"),
                        result = 3, error = 2},
        {node = create_node("int", "CONV", num(3.0), "int.num"),
                        result = 3, error = 2},
        {node = create_node("i64", "CONV", num(3.0), "i64.num"),
                        result = 3, error = 1},
        {node = create_node("i64", "CONV", num(-5.0), "i64.num"),
                        result = -5, error = 1},
        {node = create_node("int", "CONV", i64(0x100000005LL), "int.i64"),
                        result = 5, error = 1},
        {node = create_node("int", "CONV", i64(-3), "int.i64"),
                        result = -3, error = 1},
        {node = create_node("i64", "CONV", num(7.0), "i64.int sext"),
                        result = 7, error = 1},
        {node = create_node("i64", "CONV", num(-3.0), "i64.int sext"),
                        result = -3, error = 1},
        {node = create_node("num", "DIV", num(2.3), num(3.4)),
                        result = 2.3 / 3.4, error = 1.},
        {node = create_node("int", "DIV", num(23.), num(4.)),
                        result = 5, error = 1.},
        {node = create_node("num", "FLOAD", 'nil', '#226'),
                        result = -0.0, error = 0.0},
        {node = create_node("num", "FLOAD", 'nil', '#222'),
                        result = 0/0, error = 0},
        {node = create_node("int", "FLOAD", str("test_str"), "str.len"),
                        result = #"test_str", error = 1},
        {node = create_node("num", "FPMATH", num(23.3), "floor"),
		                result = math.floor(23.3), error = true},
        {node = create_node("num", "FPMATH", num(-23.3), "floor"),
		                result = math.floor(-23.3), error = true},
        {node = create_node("num", "FPMATH", num(23.3), "ceil"),
		                result = math.ceil(23.3), error = true},
        {node = create_node("num", "FPMATH", num(-23.3), "ceil"),
		                result = math.ceil(-23.3), error = true},
        {node = create_node("num", "FPMATH", num(23.3), "trunc"),
		                result = math.modf(23), error = true},
        {node = create_node("num", "FPMATH", num(-23.3), "trunc"),
		                result = math.modf(-23), error = true},
        {node = create_node("num", "FPMATH", num(4.5), "sqrt"),
		                result = math.sqrt(4.5), error = true},
        {node = create_node("num", "MAX", num(5.), num(3.)),
                        result = math.max(5., 3.), error = 3.},
        {node = create_node("int", "MAX", num(5.), num(3.)),
                        result = math.max(5., 3.), error = 3.},
        {node = create_node("int", "MAX", num(-5.), num(-3.)),
                        result = math.max(-5., -3.), error = -5.},
        {node = create_node("num", "MIN", num(5.), num(3.)),
                        result = math.min(5., 3.), error = 5.},
        {node = create_node("int", "MIN", num(5.), num(3.)),
                        result = math.min(5., 3.), error = 5.},
        {node = create_node("int", "MIN", num(-5.), num(-3.)),
                        result = math.min(-5., -3.), error = 3.},
        {node = create_node("int", "MOD", num(5), num(3)),
                        result = math.fmod(5, 3), error = 1},
        {node = create_node("num", "MUL", num(2.3), num(3.4)),
                        result = 2.3 * 3.4, error = 1.},
        {node = create_node("int", "MUL", num(2.), num(3.)),
                        result = 2 * 3, error = 1.},
        {node = create_node("int", "MULOV", num(2.), num(3.)),
                        result = 2 * 3, error = 1.},
        {node = create_node("num", "NEG", num(2.3), nil),
                        result = -2.3, error = 1.},
        {node = create_node("int", "NEG", num(2.), nil),
                        result = -2, error = 1.},
        {node = create_node("num", "SUB", num(2.3), num(3.4)),
                        result = 2.3 - 3.4, error = 1.},
        {node = create_node("int", "SUB", num(2.), num(4.)),
                        result = 2 - 4, error = 1.},
        {node = create_node("int", "SUBOV", num(2.), num(4.)),
                        result = 2 - 4, error = 1.},
        {node = create_node("int", "TOBIT", num(2.3)),
                        result = bit.tobit(2.3), error = 1.},
        {node = create_node("int", "TOBIT", num(-2.3)),
                        result = bit.tobit(-2.3), error = 1.},
        {node = create_node("int", "TOBIT", num(2147483647)),
                        result = bit.tobit(2147483647), error = 1.},
        -- Fractional power: RTZ truncates 2.5 -> 2, matching
        -- C's ldexp(double, int) cast that Lua dispatches to.
        {node = create_node("num", "LDEXP", num(3.0), num(2.5)),
                        result = math.ldexp(3.0, 2.5), error = 1.},
        {node = create_node("num", "LDEXP", num(3.0), num(-2.5)),
                        result = math.ldexp(3.0, -2.5), error = 1.},
        {node = create_node("num", "LDEXP", num(2.5), num(0)),
                        result = 2.5, error = 1.},
    }
    test:plan(3 * #nodes_to_test)
    -- Test each node in a loop.
    for i, test_case in ipairs(nodes_to_test) do
        local res = op_init .. "\n" .. translate.translate(
            { trace = { test_case.node } }, ctx_src, nil, i
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
            expected = string.format("#x%016x", test_case.result)
            unexpected = string.format("#x%016x", test_case.error)
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

    local op_init = smt_constants.LJOPT_SMTLIB ..
        ctx_src.op_stack:init_smt("op")

    local op_id = 1

    local nodes_to_test = {
        {node = create_node("int", "ADDOV", num(2.), num(3.0)),
                        result = "true", error = "false"},
        {node = create_node("int", "ADDOV",
                        num(2147483647), num(2147483647)),
                        result = "false", error = "true"},
        {node = create_node("int", "EQ", num(23.), num(23.)),
		                result = true, error = false, te=true},
        {node = create_node("num", "EQ", num(2), num(2)),
                        result = "true", error = "false"},
        {node = create_node("num", "EQ", num(2), num(2.5)),
                        result = "false", error = "true"},
        {node = create_node("int", "GE", num(23.), num(4.)),
		                result = true, error = false},
        {node = create_node("int", "GT", num(24.), num(23.)),
		                result = true, error = false},
        {node = create_node("num", "LE", num(2.3), num(3.4)),
                        result = "true", error = "false"},

        -- If any argument is NaN then result is true.
        {node = create_node("num", "UGE", num(0/0), num(3)),
                        result = "true", error = "false"},
        {node = create_node("num", "UGT", num(0/0), num(3)),
                        result = "true", error = "false"},
        {node = create_node("num", "ULE", num(0/0), num(3)),
                        result = "true", error = "false"},
        {node = create_node("num", "ULT", num(0/0), num(3)),
                        result = "true", error = "false"},
        -- And check regular arithmetic
        {node = create_node("num", "UGE", num(2), num(3)),
                        result = "false", error = "true"},
        {node = create_node("num", "UGT", num(2), num(3)),
                        result = "false", error = "true"},
        {node = create_node("num", "ULE", num(2), num(3)),
                        result = "true", error = "false"},
        {node = create_node("num", "ULT", num(2), num(3)),
                        result = "true", error = "false"},


        {node = create_node("int", "LE", num(23.), num(4.)),
		                result = false, error = true},
        {node = create_node("int", "LT", num(22.), num(23.)),
		                result = true, error = false},
        {node = create_node("int", "MULOV", num(2.), num(3.0)),
                        result = "true", error = "false"},
        {node = create_node("int", "MULOV",
                        num(2147483647), num(2147483647)),
                        result = "false", error = "true"},
        {node = create_node("num", "NE", num(2), num(2)),
                        result = "false", error = "true"},
        {node = create_node("num", "NE", num(2), num(2.5)),
                        result = "true", error = "false"},
        {node = create_node("int", "SUBOV", num(5), num(3)),
                        result = "true", error = "false"},
        {node = create_node("int", "SUBOV",
                        num(-2147483640), num(2147483647)),
                        result = "false", error = "true"},

        {node = create_node("int", "UGE", num(3), num(3)),
                        result = "true", error = "false"},
        {node = create_node("int", "UGE", num(2), num(3)),
                        result = "false", error = "true"},
        {node = create_node("int", "UGT", num(3), num(2)),
                        result = "true", error = "false"},
        {node = create_node("int", "UGT", num(3), num(3)),
                        result = "false", error = "true"},
        {node = create_node("int", "ULE", num(2), num(2)),
                        result = "true", error = "false"},
        {node = create_node("int", "ULE", num(3), num(2)),
                        result = "false", error = "true"},
        {node = create_node("int", "ULT", num(2), num(3)),
                        result = "true", error = "false"},
        {node = create_node("int", "ULT", num(3), num(3)),
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
    local addov_node = create_node("int", "ADDOV", num(2), num(3), 1)
    local conv_node = create_node("num", "CONV", ssa(1), "num.int", conv_slot)

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = smt_constants.LJOPT_SMTLIB ..
        ctx_src.op_stack:init_smt("op")

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

test:test("CONV (num.int (int.num))", function(test)
    -- 0001 >  num ADD  #x4000000000000000  #x4008000000000000
    -- 0002    num CONV   0001  int.num

    test:plan(2)

    local conv_slot = 2
    local conv_slot2 = 3
    local addov_node = create_node("num", "ADD", num(2), num(3), 1)
    local conv_node = create_node("int", "CONV", ssa(1), "int.num", conv_slot)
    local conv_node2 = create_node("num", "CONV", ssa(2), "num.int", conv_slot2)

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = smt_constants.LJOPT_SMTLIB ..
        ctx_src.op_stack:init_smt("op")

    local conv_smt1 = translate.translate(
        {trace={addov_node, conv_node}}, ctx_src, nil, nil
    )

    local expect_sat1 =
        op_init ..
        conv_smt1 ..
        ("\n(assert (= %s #x0000000000000005))"):format(
               ctx_src.op_stack:load(conv_slot, "int"), (5))
    test:is(smt:check(expect_sat1), smt.result.SAT,
        "SMT-LIB checking CONV is SAT1"
    )

    local conv_smt2 = translate.translate(
        {trace={addov_node, conv_node, conv_node2}}, ctx_src, nil, nil
    )

    local expect_sat2 =
        op_init ..
        conv_smt2 ..
        ("\n(assert (= %s ((_ to_fp 11 53) %s)))"):format(
               ctx_src.op_stack:load(conv_slot2, "num"), f2bv(5))
    test:is(smt:check(expect_sat2), smt.result.SAT,
        "SMT-LIB checking CONV is SAT2"
    )
end)

local function make_sequential_ids(limit)
    local ident = {}
    for i=1, limit do
        ident[i] = i
    end
    return ident
end

test:test("Single memory stack", function(test)
    test:plan(8)
    local mem_stack = smt_context.MemoryStack:new()
    local init_smt = mem_stack:init_smt("stack2")

    -- Allocate takes ssa_id as mandatory argument.
    local pointer, alloc_formula = mem_stack:allocate()
    local copy_ptr, copy_ptr_formula = mem_stack:allocate()
    local rewrite_slot = smt_context.create_value(
        "#x0000000000000001", op_type.I64
    )
    local const_slot = smt_context.create_value(
        "#x0000000000000002", op_type.I64
    )

    local first_value = "#x0000000000000005"
    local second_value = "#x0000000000000015"

    local final_formula = utils.join_strings({
        smt_constants.LJOPT_SMTLIB,
        init_smt,
        alloc_formula,
        mem_stack:store_index(pointer, rewrite_slot, first_value, op_type.I64),
        mem_stack:store_index(pointer, const_slot, first_value, op_type.I64),
    })
    local check_1 = ("(assert (not (= %s %s)))"):format(
        first_value,
        mem_stack:load_index(pointer, rewrite_slot, op_type.I64)
    )
    test:is(smt:parse(final_formula .. check_1), true, "Parse read after write")
    test:is(smt:check(final_formula .. check_1),
        smt.result.UNSAT, "Check read after write"
    )

    final_formula = final_formula .. utils.join_strings({
        mem_stack:store_index(pointer, rewrite_slot, second_value, op_type.I64),
    })
    local check_2 = ("(assert (not (= %s %s)))"):format(
        second_value,
        mem_stack:load_index(pointer, rewrite_slot, op_type.I64)
    )
    test:is(smt:parse(final_formula .. check_2),
        true, "Parse read after rewrite"
    )
    test:is(smt:check(final_formula .. check_2), smt.result.UNSAT,
        "Check read after rewrite"
    )

    final_formula = final_formula .. utils.join_strings({
        copy_ptr_formula,
        mem_stack:store(copy_ptr, mem_stack:load(pointer)),
    })
    -- 3rd and 4th checks: we copy correctly.
    local check3 = ("(assert (not (= %s %s)))"):format(
        second_value,
        mem_stack:load_index(copy_ptr, rewrite_slot, op_type.I64)
    )
    test:is(smt:parse(final_formula .. check3), true, "Parse copy rewrite")
    test:is(smt:check(final_formula .. check3),
        smt.result.UNSAT, "Check copy rewrite"
    )
    local check4 = ("(assert (not (= %s %s)))"):format(
        first_value,
        mem_stack:load_index(copy_ptr, const_slot, op_type.I64)
    )
    test:is(smt:parse(final_formula .. check4), true, "Parse copy write once")
    test:is(smt:check(final_formula .. check4),
        smt.result.UNSAT, "Check copy write once"
    )
end)


-- In this stack we check that shared memory is indeed shared,
-- both child stack should be equal to their base,
-- if not rewritten.
test:test("Shared memory stack", function(test)
    test:plan(10)
    do
        local no_base_stack1 = smt_context.MemoryStack:new()
        local no_base_stack2 = smt_context.MemoryStack:new()

        local no_base_formula = utils.join_strings({
            smt_constants.LJOPT_SMTLIB,
            no_base_stack1:init_smt("no_base1"),
            no_base_stack2:init_smt("no_base2"),
            ("(assert (not (= %s %s)))"):format(
                no_base_stack1:load("1"), no_base_stack2:load("1")
            ),
        })
        -- If no base stack => unequal.
        test:is(smt:parse(no_base_formula), true, "Parsing no base equality")
        test:is(smt:check(no_base_formula),
            smt.result.SAT, "Checking SAT for not shared memory"
        )
    end
    do
        local base_stack1 = smt_context.MemoryStack:new()
        local has_base_stack1 = smt_context.MemoryStack:new()
        local has_base_stack2 = smt_context.MemoryStack:new()

        local has_base_formula = utils.join_strings({
            smt_constants.LJOPT_SMTLIB,
            base_stack1:init_smt("base_stack1"),
            has_base_stack1:init_smt("has_base_stack1", base_stack1),
            has_base_stack2:init_smt("has_base_stack2", base_stack1),
        })
        local st1, clone1 = has_base_stack1:allocate()
        local st2, clone2 = has_base_stack2:allocate()
        has_base_formula = has_base_formula .. utils.join_strings({
            clone1,
            clone2,
            ("(assert (not (= %s %s)))"):format(
                has_base_stack1:load(st1), has_base_stack2:load(st2)
            ),
        })

        -- If base stack => equal.
        test:is(smt:parse(has_base_formula), true, "Parsing shared memory")
        test:is(smt:check(has_base_formula),
            smt.result.UNSAT, "Checking UNSAT in shared memory"
        )
    end
    do
        local base_stack = smt_context.MemoryStack:new()

        local mem_stack1 = smt_context.MemoryStack:new()
        local mem_stack2 = smt_context.MemoryStack:new()

        local slot1 = smt_context.create_value(
            "#x0000000000000005", op_type.I64
        )
        local first_value = "#x0000000000000005"
        local second_value = "#x0000000000000015"

        local slots_init_formula = utils.join_strings({
            smt_constants.LJOPT_SMTLIB,
            base_stack:init_smt("base_stack"),
            mem_stack1:init_smt("mem_stack1", base_stack),
            mem_stack2:init_smt("mem_stack2", base_stack),
        })
        local st1, clone1 = mem_stack1:allocate()
        local st2, clone2 = mem_stack2:allocate()
        slots_init_formula = utils.join_strings({
            slots_init_formula,
            clone1,
            clone2,
            mem_stack1:store_index(st1, slot1, first_value, op_type.I64),
            mem_stack2:store_index(st2, slot1, second_value, op_type.I64),
        })
        local test_formula1 = utils.join_strings({
            slots_init_formula,
            ("(assert (= %s %s))"):format(
                mem_stack1:load(st1), mem_stack2:load(st2)
            ),
        })
        test:is(smt:parse(test_formula1), true,
            "Parse different values equality"
        )
        test:is(smt:check(test_formula1),
            smt.result.UNSAT, "Check different values equality is UNSAT"
        )

        local test_formula2 = utils.join_strings({
            slots_init_formula,
            ("(assert (not (= %s %s)))"):format(
                mem_stack1:load(st1), mem_stack2:load(st2)
            ),
        })
        test:is(smt:parse(test_formula2), true, "Parse different values")
        test:is(smt:check(test_formula2),
            smt.result.SAT, "Check different values not-equal is SAT"
        )

        local test_formula3 = utils.join_strings({
            slots_init_formula,
            mem_stack1:store_index(st1, slot1, first_value, op_type.I64),
            mem_stack2:store_index(st2, slot1, second_value, op_type.I64),
            mem_stack2:store_index(st2, slot1, first_value, op_type.I64),
            ("(assert (not (= %s %s)))"):format(
                mem_stack1:load(st1), mem_stack2:load(st2)
            ),
        })
        test:is(smt:parse(test_formula3), true, "Parse same values")
        test:is(smt:check(test_formula3),
            smt.result.UNSAT, "Check same values"
        )
    end
end)

test:test("Memory IRs tests", function(test)
    test:plan(2)

    local base_stack = smt_context.MemoryStack:new()
    local base_init = base_stack:init_smt("base")

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = ctx_src.op_stack:init_smt("op")
    local vm_init = ctx_src.vm_stack:init_smt("vm")
    local mem_init = ctx_src.mem_stack:init_smt("mem", base_stack)

    local prefix = utils.join_strings({
        smt_constants.LJOPT_SMTLIB,
        base_init,
        op_init,
        vm_init,
        mem_init,
    })
    local nodes = {
        create_node("tab", "SLOAD", imm(1), nil, 1),
        create_node("p32", "NEWREF", ssa(1), num(11), 2),
        create_node("num", "HSTORE", ssa(2), num(1), 3),

        create_node("p32", "HREF", ssa(1), num(11), 4),
        create_node("num", "HLOAD", ssa(4), nil, 5),

        create_node("num", "HSTORE", ssa(2), num(2), 3),

        create_node("num", "HLOAD", ssa(4), nil, 6)
    }
    local trace = {
        trace = nodes,
        ssa_ref2id = make_sequential_ids(6),
    }

    local conv_smt = translate.translate(
        trace, ctx_src, nil, nil, {mem_stack=base_stack}
    )

    -- luacheck: push no max_line_length
    local expect_sat =
        prefix .. conv_smt ..
        "(assert (= (get-bv (select (select (select mem 1) 1) (int-val #x4026000000000000))) #x3FF0000000000000))" .. "\n" ..
        "(assert (= (get-bv (select (select (select mem 2) 1) (int-val #x4026000000000000))) #x3F00000000000000))" .. "\n"
    -- luacheck: pop
    test:is(smt:parse(expect_sat), true, "Parse memory operations")
    test:is(smt:check(expect_sat), smt.result.SAT, "Ensure memory correct")
end)

test:test("Array IRs tests", function(test)
    test:plan(2)

    local base_stack = smt_context.MemoryStack:new()
    local base_init = base_stack:init_smt("base")

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = ctx_src.op_stack:init_smt("op")
    local vm_init = ctx_src.vm_stack:init_smt("vm")
    local mem_init = ctx_src.mem_stack:init_smt("mem", base_stack)

    local prefix = utils.join_strings({
        smt_constants.LJOPT_SMTLIB,
        base_init,
        op_init,
        vm_init,
        mem_init,
    })
    local nodes = {
        create_node("tab", "SLOAD", imm(1), nil, 1),
        create_node("p32", "NEWREF", ssa(1), num(11), 2),
        create_node("num", "ASTORE", ssa(2), num(1), 3),

        create_node("p32", "AREF", ssa(1), num(11), 4),
        create_node("num", "ALOAD", ssa(4), nil, 5),

        create_node("num", "ASTORE", ssa(2), num(1), 3),

        create_node("num", "ALOAD", ssa(4), nil, 6)
    }
    local trace = {
        trace = nodes,
        ssa_ref2id = make_sequential_ids(6),
    }

    local conv_smt = translate.translate(
        trace, ctx_src, nil, nil, {mem_stack=base_stack}
    )

    -- luacheck: push no max_line_length
    local expect_sat =
        prefix .. conv_smt ..
        "(assert (= (get-bv (select (select (select mem 1) 1) (int-val #x4026000000000000))) #x3FF0000000000000))" .. "\n" ..
        "(assert (= (get-bv (select (select (select mem 2) 1) (int-val #x4026000000000000))) #x3F00000000000000))" .. "\n"
    -- luacheck: pop
    test:is(smt:parse(expect_sat), true, "Parse memory operations")
    test:is(smt:check(expect_sat), smt.result.SAT, "Ensure memory correct")
end)


test:test("TNEW test", function(test)
    test:plan(2)

    local base_stack = smt_context.MemoryStack:new()
    local base_init = base_stack:init_smt("base")

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = ctx_src.op_stack:init_smt("op")
    local vm_init = ctx_src.vm_stack:init_smt("vm")
    local mem_init = ctx_src.mem_stack:init_smt("mem", base_stack)

    local prefix = utils.join_strings({
        smt_constants.LJOPT_SMTLIB,
        base_init,
        op_init,
        vm_init,
        mem_init,
    })
    local nodes = {
        create_node("tab", "TNEW", imm(1), imm(1), 1),
        create_node("p32", "NEWREF", ssa(1), num(11), 2),
        create_node("num", "HSTORE", ssa(2), num(1), 3),

        create_node("p32", "HREF", ssa(1), num(11), 4),
        create_node("num", "HLOAD", ssa(4), nil, 5),

        create_node("num", "HSTORE", ssa(2), num(2), 3),

        create_node("num", "HLOAD", ssa(4), nil, 6)
    }
    local trace = {
        trace = nodes,
        ssa_ref2id = make_sequential_ids(6),
    }

    local conv_smt = translate.translate(
        trace, ctx_src, nil, nil, {mem_stack=base_stack}
    )

    -- luacheck: push no max_line_length
    local expect_sat =
        prefix .. conv_smt ..
        "(assert (= (get-bv (select (select (select mem 0) 1) (int-val #x4026000000000000))) #x3FF0000000000000))" .. "\n" ..
        "(assert (= (get-bv (select (select (select mem 0) 2) (int-val #x4026000000000000))) #x4000000000000000))" .. "\n"
    -- luacheck: pop
    test:is(smt:parse(expect_sat), true, "Parse memory operations")
    test:is(smt:check(expect_sat), smt.result.SAT, "Ensure memory correct")
end)

test:test("CONV from i64", function(test)
    -- 0001    i64 CONV   num(3.0)  i64.num
    -- 0002    num CONV   0001      num.i64

    test:plan(2)

    local conv_slot = 2
    local i64_node = create_node("i64", "CONV", num(3.0), "i64.num", 1)
    local num_node = create_node("num", "CONV", ssa(1), "num.i64", conv_slot)

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = smt_constants.LJOPT_SMTLIB ..
        ctx_src.op_stack:init_smt("op")

    local conv_smt = translate.translate(
        {trace={i64_node, num_node}}, ctx_src, nil, nil
    )

    -- i64.num converts 3.0 to integer 3.
    -- num.i64 converts integer 3 back to float 3.0.
    local expect_sat =
        op_init ..
        conv_smt ..
        ("\n(assert (= %s ((_ to_fp 11 53) %s)))"):format(
            ctx_src.op_stack:load(conv_slot, "num"), f2bv(3)
        )
    test:is(smt:check(expect_sat), smt.result.SAT,
        "SMT-LIB checking CONV i64.num -> num.i64 is SAT"
    )

    local expect_unsat =
        op_init ..
        conv_smt ..
        ("\n(assert (= %s ((_ to_fp 11 53) %s)))"):format(
            ctx_src.op_stack:load(conv_slot, "num"), f2bv(99)
        )
    test:is(smt:check(expect_unsat), smt.result.UNSAT,
        "SMT-LIB checking CONV i64.num -> num.i64 wrong is UNSAT"
    )
end)

-- Exercises the `nil-val` MemCell: a value cell is not nil-val,
-- and storing nil over a key makes it read back as nil-val.
test:test("Nil memory cell", function(test)
    test:plan(5)

    -- create_value maps the nil op-type to the 0-arg nil-val
    -- constructor.
    test:is(smt_context.create_value("ignored", op_type.NIL), "nil-val",
        "create_value NIL -> nil-val"
    )

    local mem_stack = smt_context.MemoryStack:new()
    local init_smt = mem_stack:init_smt("nilstack")
    local pointer, alloc_formula = mem_stack:allocate()
    local key = smt_context.create_value("#x0000000000000001", op_type.I64)
    local value = "#x0000000000000005"

    -- Write a real value to the key.
    local base = utils.join_strings({
        smt_constants.LJOPT_SMTLIB,
        init_smt,
        alloc_formula,
        mem_stack:store_index(pointer, key, value, op_type.I64),
    })
    local value_cell = ("(select %s %s)"):format(mem_stack:load(pointer), key)
    -- The int-val cell is not nil-val, so asserting it is unsat.
    local non_nil = ("(assert ((_ is nil-val) %s))"):format(value_cell)
    test:is(smt:parse(base .. non_nil), true, "Parse value cell")
    test:is(smt:check(base .. non_nil), smt.result.UNSAT,
        "Value cell is not nil-val"
    )

    -- Overwrite the key with nil; the cell now reads back as
    -- nil-val.
    local with_nil = base .. utils.join_strings({
        mem_stack:store_index(pointer, key, "nil-val", op_type.NIL),
    })
    local nil_cell = ("(select %s %s)"):format(mem_stack:load(pointer), key)
    local is_nil = ("(assert (not ((_ is nil-val) %s)))"):format(nil_cell)
    test:is(smt:parse(with_nil .. is_nil), true, "Parse nil cell")
    test:is(smt:check(with_nil .. is_nil), smt.result.UNSAT,
        "Deleted cell reads back as nil-val"
    )
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
