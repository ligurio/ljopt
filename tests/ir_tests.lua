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

test:plan(6)

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
        flags = {
            irt_guard = nil,
            irt_isphi = nil,
        },
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
        {node = create_node("num", "ABS", f2bv(-2.3)),
		                result = 2.3, error = 1.},
        {node = create_node("int", "ABS", f2bv(-2.)),
		                result = 2, error = 1.},
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
        {node = create_node("int", "BROL", f2bv(124245235), f2bv(2)),
                        result = bit.rol(124245235, 2), error = 1.},
        {node = create_node("int", "BROR", f2bv(124245235), f2bv(2)),
                        result = bit.ror(124245235, 2), error = 1.},
        {node = create_node("int", "BSAR", f2bv(124245235), f2bv(2)),
                        result = bit.rshift(124245235, 2), error = 1.},
        {node = create_node("int", "BSHL", f2bv(124245235), f2bv(2)),
                        result = bit.lshift(124245235, 2), error = 1.},
        {node = create_node("int", "BSHR", f2bv(124245235), f2bv(2)),
                        result = bit.rshift(124245235, 2), error = 1.},
        {node = create_node("int", "BSWAP", f2bv(124245235)),
                        result = bit.bswap(124245235), error = 1.},
        {node = create_node("int", "BXOR", f2bv(124245235), f2bv(2)),
                        result = bit.bxor(124245235, 2), error = 1.},
        {node = create_node("num", "CONV", f2bv(3.0), "num.int"),
                        result = 3, error = 2},
        {node = create_node("int", "CONV", f2bv(3.0), "int.num"),
                        result = 3, error = 2},
        {node = create_node("num", "DIV", f2bv(2.3), f2bv(3.4)),
                        result = 2.3 / 3.4, error = 1.},
        {node = create_node("int", "DIV", f2bv(23.), f2bv(4.)),
                        result = 5, error = 1.},
        {node = create_node("num", "FPMATH", f2bv(23.3), "floor"),
		                result = math.floor(23.3), error = true},
        {node = create_node("num", "FPMATH", f2bv(-23.3), "floor"),
		                result = math.floor(-23.3), error = true},
        {node = create_node("num", "FPMATH", f2bv(23.3), "ceil"),
		                result = math.ceil(23.3), error = true},
        {node = create_node("num", "FPMATH", f2bv(-23.3), "ceil"),
		                result = math.ceil(-23.3), error = true},
        {node = create_node("num", "FPMATH", f2bv(23.3), "trunc"),
		                result = math.modf(23), error = true},
        {node = create_node("num", "FPMATH", f2bv(-23.3), "trunc"),
		                result = math.modf(-23), error = true},
        {node = create_node("num", "FPMATH", f2bv(4.5), "sqrt"),
		                result = math.sqrt(4.5), error = true},
        {node = create_node("num", "MAX", f2bv(5.), f2bv(3.)),
                        result = math.max(5., 3.), error = 3.},
        {node = create_node("int", "MAX", f2bv(5.), f2bv(3.)),
                        result = math.max(5., 3.), error = 3.},
        {node = create_node("int", "MAX", f2bv(-5.), f2bv(-3.)),
                        result = math.max(-5., -3.), error = -5.},
        {node = create_node("num", "MIN", f2bv(5.), f2bv(3.)),
                        result = math.min(5., 3.), error = 5.},
        {node = create_node("int", "MIN", f2bv(5.), f2bv(3.)),
                        result = math.min(5., 3.), error = 5.},
        {node = create_node("int", "MIN", f2bv(-5.), f2bv(-3.)),
                        result = math.min(-5., -3.), error = 3.},
        {node = create_node("int", "MOD", f2bv(5), f2bv(3)),
                        result = math.fmod(5, 3), error = 1},
        {node = create_node("num", "MUL", f2bv(2.3), f2bv(3.4)),
                        result = 2.3 * 3.4, error = 1.},
        {node = create_node("int", "MUL", f2bv(2.), f2bv(3.)),
                        result = 2 * 3, error = 1.},
        {node = create_node("int", "MULOV", f2bv(2.), f2bv(3.)),
                        result = 2 * 3, error = 1.},
        {node = create_node("num", "NEG", f2bv(2.3), nil),
                        result = -2.3, error = 1.},
        {node = create_node("int", "NEG", f2bv(2.), nil),
                        result = -2, error = 1.},
        {node = create_node("num", "SUB", f2bv(2.3), f2bv(3.4)),
                        result = 2.3 - 3.4, error = 1.},
        {node = create_node("int", "SUB", f2bv(2.), f2bv(4.)),
                        result = 2 - 4, error = 1.},
        {node = create_node("int", "SUBOV", f2bv(2.), f2bv(4.)),
                        result = 2 - 4, error = 1.},
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

        -- If any argument is NaN then result is true.
        {node = create_node("num", "UGE", f2bv(0/0), f2bv(3)),
                        result = "true", error = "false"},
        {node = create_node("num", "UGT", f2bv(0/0), f2bv(3)),
                        result = "true", error = "false"},
        {node = create_node("num", "ULE", f2bv(0/0), f2bv(3)),
                        result = "true", error = "false"},
        {node = create_node("num", "ULT", f2bv(0/0), f2bv(3)),
                        result = "true", error = "false"},
        -- And check regular arithmetic
        {node = create_node("num", "UGE", f2bv(2), f2bv(3)),
                        result = "false", error = "true"},
        {node = create_node("num", "UGT", f2bv(2), f2bv(3)),
                        result = "false", error = "true"},
        {node = create_node("num", "ULE", f2bv(2), f2bv(3)),
                        result = "true", error = "false"},
        {node = create_node("num", "ULT", f2bv(2), f2bv(3)),
                        result = "true", error = "false"},


        {node = create_node("int", "LE", f2bv(23.), f2bv(4.)),
		                result = false, error = true},
        {node = create_node("int", "LT", f2bv(22.), f2bv(23.)),
		                result = true, error = false},
        {node = create_node("int", "MULOV", f2bv(2.), f2bv(3.0)),
                        result = "true", error = "false"},
        {node = create_node("int", "MULOV",
                        f2bv(2147483647), f2bv(2147483647)),
                        result = "false", error = "true"},
        {node = create_node("num", "NE", f2bv(2), f2bv(2)),
                        result = "false", error = "true"},
        {node = create_node("num", "NE", f2bv(2), f2bv(2.5)),
                        result = "true", error = "false"},
        {node = create_node("int", "SUBOV", f2bv(5), f2bv(3)),
                        result = "true", error = "false"},
        {node = create_node("int", "SUBOV",
                        f2bv(-2147483640), f2bv(2147483647)),
                        result = "false", error = "true"},

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

test:test("CONV (num.int (int.num))", function(test)
    -- 0001 >  num ADD  #x4000000000000000  #x4008000000000000
    -- 0002    num CONV   0001  int.num

    test:plan(2)

    local conv_slot = 2
    local conv_slot2 = 3
    local addov_node = create_node("num", "ADD", f2bv(2), f2bv(3), 1)
    local conv_node = create_node("int", "CONV", "0001", "int.num", conv_slot)
    local conv_node2 = create_node("num", "CONV", "0002", "num.int", conv_slot2)

    local ctx_src = smt_context.SMTContext:new("BV", "BV")

    local op_init = ctx_src.op_stack:init_smt("op")

    local conv_smt1 = translate.translate(
        {trace={addov_node, conv_node}}, ctx_src, nil, nil
    )

    local expect_sat1 =
        op_init ..
        conv_smt1 ..
        ("\n(assert (= %s #x0000000000000005))"):format(
               ctx_src.op_stack:load(conv_slot, "int"), f2bv(5))
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

local function join_strings(string_array)
    local joined = ""
    for _, formula in ipairs(string_array) do
        joined = joined .. "\n" .. formula
    end
    return joined
end

test:test("Single memory stack", function(test)
    test:plan(8)
    local mem_stack = smt_context.MemoryStack:new()
    local init_smt = mem_stack:init_smt("stack2")
    local pointer = 2
    local copy_ptr = 3
    local rewrite_slot = 1
    local const_slot = 2

    local first_value = "#x0000000000000005"
    local second_value = "#x0000000000000015"

    local final_formula = join_strings({
        mem_stack:init_smt("stack2"),
        mem_stack:store_index(pointer, rewrite_slot, first_value),
        mem_stack:store_index(pointer, const_slot, first_value),
    })
    local check_1 = ("(assert (not (= %s %s)))"):format(
        first_value, mem_stack:load_index(pointer, rewrite_slot)
    )
    test:is(smt:parse(final_formula .. check_1), true, "parse read after write")
    test:is(smt:check(final_formula .. check_1), smt.result.UNSAT, "check read after write")

    final_formula = final_formula .. join_strings({
        mem_stack:store_index(pointer, rewrite_slot, second_value),
    })
    local check_2 = ("(assert (not (= %s %s)))"):format(
        second_value, mem_stack:load_index(pointer, rewrite_slot)
    )
    test:is(smt:parse(final_formula .. check_2), true, "parse read after rewrite")
    test:is(smt:check(final_formula .. check_2), smt.result.UNSAT, "check read after rewrite")

    final_formula = final_formula .. join_strings({
        mem_stack:store(copy_ptr, mem_stack:load(pointer)),
    })
        -- 3 and 4-th checks, we copy correctly.
    local check3 = ("(assert (not (= %s %s)))"):format(second_value, mem_stack:load_index(copy_ptr, rewrite_slot))
    test:is(smt:parse(final_formula .. check3), true, "parse whole copy rewrite")
    test:is(smt:check(final_formula .. check3), smt.result.UNSAT, "check whole copy rewrite")
    local check4 = ("(assert (not (= %s %s)))"):format(first_value, mem_stack:load_index(copy_ptr, const_slot))
    test:is(smt:parse(final_formula .. check4), true, "parse whole copy write once")
    test:is(smt:check(final_formula .. check4), smt.result.UNSAT, "parse whole copy write once")
end)


-- In this stack we check that shared memory is indeed shared,
-- both child stack should be equal to their base,
-- if not rewritten.
test:test("Shared memory stack", function(test)
    test:plan(8)
    do
        local no_base_stack1 = smt_context.MemoryStack:new()
        local no_base_stack2 = smt_context.MemoryStack:new()

        local no_base_formula = join_strings({
            no_base_stack1:init_smt("no_base1"),
            no_base_stack2:init_smt("no_base2"),
            ("(assert (not (= %s %s)))"):format(no_base_stack1:load(1), no_base_stack2:load(1)),
        })
        -- If no base stack => unequal.
        test:is(smt:parse(no_base_formula), true, "parsing no base equality")
        test:is(smt:check(no_base_formula), smt.result.SAT, "checking SAT for not shared memory")
    end
    do
        local base_stack1 = smt_context.MemoryStack:new()
        local has_base_stack1 = smt_context.MemoryStack:new()
        local has_base_stack2 = smt_context.MemoryStack:new()

        local has_base_formula = join_strings({
            base_stack1:init_smt("base_stack1"),
            has_base_stack1:init_smt("has_base_stack1", base_stack1),
            has_base_stack2:init_smt("has_base_stack2", base_stack1),
        })
        local st1, clone1 = has_base_stack1:allocate(1)
        local st2, clone2 = has_base_stack2:allocate(1)
        has_base_formula = has_base_formula .. join_strings({
            clone1,
            clone2,
            ("(assert (not (= %s %s)))"):format(has_base_stack1:load(st1), has_base_stack2:load(st2)),
        })

        -- If base stack => equal.
        test:is(smt:parse(has_base_formula), true, "parsing shared memory")
        test:is(smt:check(has_base_formula), smt.result.UNSAT, "checking UNSAT in shared memory")
    end
    do
        local base_stack = smt_context.MemoryStack:new()

        local mem_stack1 = smt_context.MemoryStack:new()
        local mem_stack2 = smt_context.MemoryStack:new()

        local slot1 = 1
        local first_value = "#x0000000000000005"
        local second_value = "#x0000000000000015"

        local final_formula = join_strings({
            base_stack:init_smt("base_stack"),
            mem_stack1:init_smt("mem_stack1", base_stack),
            mem_stack2:init_smt("mem_stack2", base_stack),
        })
        local st1, clone1 = mem_stack1:allocate(1)
        local st2, clone2 = mem_stack2:allocate(1)
        final_formula = final_formula .. join_strings({
            clone1,
            clone2,
            ("(assert (not (= %s %s)))"):format(mem_stack1:load(st1), mem_stack2:load(st2)),
        })

        local final_formula = final_formula .. join_strings({
            mem_stack1:store_index(st1, slot1, first_value),
            mem_stack2:store_index(st2, slot1, second_value),
            ("(assert (= %s %s))"):format(
                mem_stack1:load(st1), mem_stack2:load(st2)
            ),
        })
        test:is(smt:parse(final_formula), true, "parse different values")
        test:is(smt:check(final_formula), smt.result.UNSAT, "check different values")

        final_formula = final_formula .. join_strings({
            mem_stack2:store_index(st2, slot1, first_value),
            ("(assert (not (= %s %s)))"):format(
                mem_stack1:load(st1), mem_stack2:load(st1)
            ),
        })
        test:is(smt:parse(final_formula), true, "parse same values")
        test:is(smt:check(final_formula), smt.result.UNSAT, "check same values")
    end
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
