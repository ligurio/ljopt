-- This file contains general unit tests
-- to tests correctnes of arbitrary
-- data structures we use.

local ljopt = require("ljopt")
local arith_utils = require("ljopt.ir.arith_utils")
local ljopt_config = require("ljopt.config")
local loop_unrolling = require("ljopt.loop_unrolling")
local utils = require("ljopt.utils")

local smt = require("tests.smtlib2").new()
local test = require("tests.tap").test("ljopt")

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
require("tests.coverage").enable()

local function expect_fail(test, name, fun, ...)
    local success, _ = pcall(fun, ...)
    test:is(success, false, name)
end

test:plan(8)

test:test("merge_tables", function(test)
    test:plan(10)
    -- Test 1: Basic functionality with string keys
    local t1 = {a = 1, b = 2, c = 3}
    local t2 = {a = 10, b = 20, c = 30}
    local result = utils.merge_tables(t1, t2)
    test:is(result.a[1], 1, "Wrong a[1]")
    test:is(result.b[1], 2, "Wrong b[1]")
    test:is(result.c[1], 3, "Wrong c[1]")
    test:is(result.a[2], 10, "Wrong a[2]")
    test:is(result.b[2], 20, "Wrong b[2]")
    test:is(result.c[2], 30, "Wrong c[2]")


    -- Failure tests requires to be run in strict mode to
    -- trigger assertion.
    local strict_mode = ljopt_config.is_strict_mode()
    ljopt_config.set_strict_mode(true)

    -- Missing 'c'.
    expect_fail(test, "Left missing c", utils.merge_tables,
        {a = 1, b = 2},
		{a = 1, b = 2, c = 3})
    expect_fail(test, "Right missing c", utils.merge_tables,
	    {a = 1, b = 2, c = 3},
		{a = 1, b = 2})

    -- nil value.
    expect_fail(test, "Left nil", utils.merge_tables,
	    {a = nil},
		{a = 1})
    expect_fail(test, "Right nil", utils.merge_tables,
	    {a = 1},
		{a = nil})
    ljopt_config.set_strict_mode(strict_mode)
end)

test:test("Arithmetic utils tests", function(test)
    test:plan(3)
    local no_overflow = arith_utils.i32_overflow_check("#x000000007fffffff")
    local max_i32_inc = "#x0000000080000000"
    local positive_overflow = arith_utils.i32_overflow_check(max_i32_inc)
    local min_i32_dec = "#xffffffff7fffffff"
    local negative_overflow = arith_utils.i32_overflow_check(min_i32_dec)

    test:is(smt:check(("(assert %s)"):format(no_overflow)),
        smt.result.SAT, "SMT-LIB check no i32 overflow"
    )
    test:is(smt:check(("(assert %s)"):format(positive_overflow)),
        smt.result.UNSAT, "SMT-LIB check positive i32 overflow"
    )
    test:is(smt:check(("(assert %s)"):format(negative_overflow)),
        smt.result.UNSAT, "SMT-LIB check negative i32 overflow"
    )
end)

test:test("Trace exit merge snapshots", function(test)
    test:plan(4)
    local snapshots = {}
    snapshots[1] = {nins={1}}
    snapshots[3] = {nins={3}}

    local create_node = function()
        -- It will be extended later.
        return {
            get_flags = function(self)
                return {irt_guard = true}
            end,
        }
    end

    local nodes = {}
    nodes[1] = create_node()
    nodes[2] = create_node()
    nodes[3] = create_node()
    nodes[4] = create_node()

    local all_trace = {snapshots=snapshots}
    utils.enrich_snapshots_with_exits(nodes, all_trace)
    local snaps = all_trace.snapshots
    test:is(snaps[1].exits[1], 1, "1 guard matched with 1 snapshot")
    test:is(snaps[1].exits[2], 2, "2 guard matched with 1 snapshot")
    test:is(snaps[3].exits[1], 3, "3 guard matched with 3 snapshot")
    test:is(snaps[3].exits[2], 4, "4 guard matched with 3 snapshot")

end)

test:test("arith_utils conversion functions", function(test)
    test:plan(10)

    -- const_int_to_smt_bv:
    -- string.format %016X, no truncation.
    test:is(arith_utils.const_int_to_smt_bv(0),
        "#x0000000000000000", "const_int_to_smt_bv: zero")
    test:is(arith_utils.const_int_to_smt_bv(1),
        "#x0000000000000001", "const_int_to_smt_bv: one")
    test:is(arith_utils.const_int_to_smt_bv(256),
        "#x0000000000000100", "const_int_to_smt_bv: 256")
    -- string.format preserves full 64-bit value.
    test:is(arith_utils.const_int_to_smt_bv(2^32 + 1),
        "#x0000000100000001", "const_int_to_smt_bv: full 64-bit")
    test:is(arith_utils.const_int_to_smt_bv(-1),
        "#xFFFFFFFFFFFFFFFF", "const_int_to_smt_bv: -1")
    test:is(arith_utils.const_int_to_smt_bv(-256),
        "#xFFFFFFFFFFFFFF00", "const_int_to_smt_bv: -256")

    -- Ensure these conversions equivalent:
    -- 1. int -> smt_int_bv -> smt_fp.
    -- 2. fp -> smt_fp
    local smt_int = arith_utils.const_int_to_smt_bv(-2^31)
    local smt_fp = arith_utils.const_num_to_smt_fp(-2^31)
    test:is(smt:check(("(assert (= %s %s))"):format(
            smt_fp, arith_utils.smt_int_to_fp(smt_int)
        )), smt.result.SAT, "Int32 min -> FP conversion"
    )

    local smt_neg1_int = arith_utils.const_int_to_smt_bv(-1)
    local smt_neg1_fp = arith_utils.const_num_to_smt_fp(-1)
    test:is(smt:check(("(assert (= %s %s))"):format(
            smt_neg1_fp, arith_utils.smt_int_to_fp(smt_neg1_int)
        )), smt.result.SAT, "Int -1 -> FP conversion"
    )

    local smt_neg256_int = arith_utils.const_int_to_smt_bv(-256)
    local smt_neg256_fp = arith_utils.const_num_to_smt_fp(-256)
    test:is(smt:check(("(assert (= %s %s))"):format(
            smt_neg256_fp, arith_utils.smt_int_to_fp(smt_neg256_int)
        )), smt.result.SAT, "Int -256 -> FP conversion"
    )

    -- 0x0000000080000000: lower 32 bits = INT32_MIN as i32.
    test:is(smt:check(("(assert (= %s %s))"):format(
            arith_utils.smt_int_to_fp("#x0000000080000000"),
            arith_utils.const_num_to_smt_fp(-2^31)
        )), smt.result.SAT, "i32 sign-extend 0x80000000 -> FP -2^31"
    )
end)

test:test("mark_narrowed_refs", function(test)
    local ir_passes = require("ljopt.ir_passes")

    test:plan(3)

    local function ssa(n) return { _is_ssa = true, _v = n,
        is_ssa = function(self) return self._is_ssa end,
        get_ssa = function(self) return self._v end } end
    local function lit(s) return { _is_ssa = false, _v = s,
        is_ssa = function(self) return self._is_ssa end,
        get_lit = function(self) return self._v end } end
    local function node(opcode, type, sref, left, right)
        return {
            _sref = sref, _op = opcode, _type = type,
            _left = left, _right = right,
            get_ssa_reference = function(self) return self._sref end,
            get_opcode = function(self) return self._op end,
            get_type = function(self) return self._type end,
            get_left_op = function(self) return self._left end,
            get_right_op = function(self) return self._right end,
        }
    end
    local function fresh_ctx()
        return {
            te_stack = { narrowed_refs = {} }
        }
    end

    -- SLOAD-C -> LE -> LE. Only the first LE (direct SLOAD-C
    -- operand) is marked; the chained LE on its result is not
    -- (mark_narrowed_refs only propagates one hop from SLOAD-C).
    local ctx = fresh_ctx()
    ir_passes.mark_narrowed_refs({
        node('SLOAD', 'int', 1, lit('#5'), lit('CRI')),
        node('LE', 'int', 2, ssa(1), lit('#x7ffffffe')),
        node('LE', 'int', 3, ssa(2), lit('#x7ffffffe')),
    }, ctx)
    test:is(ctx.te_stack.narrowed_refs[2], true,
        "LE on SLOAD-C + const marked")
    test:is(ctx.te_stack.narrowed_refs[3], nil,
        "chained LE on non-SLOAD-C operand not marked")

    -- LE whose operand is a stray SSA ref (no SLOAD-C anywhere):
    -- not marked.
    ctx = fresh_ctx()
    ir_passes.mark_narrowed_refs({
        node('LE', 'int', 1, ssa(99), lit('#x7ffffffe')),
    }, ctx)
    test:is(ctx.te_stack.narrowed_refs[1], nil,
        "LE on stray ref not marked")
end)

local LOOP_CHUNK = [[
local sin = math.sin
local res = 0.0
for i = 1, 100 do res = res + sin(i) end
]]

local OPT_LEVELS = {
    unopt = "jit.opt.start(0, 'hotloop=1', 'hotexit=1')",
    opt = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')",
}

local function recorded_loop_trace(level)
    local records = ljopt.ir.record(LOOP_CHUNK, OPT_LEVELS[level])
    assert(type(records) == 'table', tostring(records))
    local found
    for _, trace in pairs(records) do
        assert(found == nil, 'expected a single recorded trace')
        found = trace
    end
    assert(found ~= nil, 'nothing was recorded')
    return found
end

local function unroll_at(depth, trace, op_stack)
    local unroll_n = ljopt_config.get_loop_unroll_limit()
    ljopt_config.set_loop_unroll_limit(depth)
    local nodes, snaps, smt_out = loop_unrolling.loop_unrooling_transform(
        trace.trace, trace.snapshots, trace.linktype, op_stack
    )
    ljopt_config.set_loop_unroll_limit(unroll_n)
    return nodes, snaps, smt_out
end

local function count_irop(nodes, irop)
    local found = 0
    for _, node in ipairs(nodes) do
        if node.irop == irop then found = found + 1 end
    end
    return found
end

local function count_duplicates(refs)
    local seen, dups = {}, 0
    for _, ref in ipairs(refs) do
        if seen[ref] then dups = dups + 1 end
        seen[ref] = true
    end
    return dups
end

test:test("loop unrolling at depth 0", function(test)
    test:plan(4)

    local opt = recorded_loop_trace('opt')
    local loop_idx
    for i, node in ipairs(opt.trace) do
        if node.irop == 'LOOP' then loop_idx = i break end
    end
    test:ok(loop_idx ~= nil, "the opt trace carries a LOOP marker")

    local nodes = unroll_at(0, opt)
    test:is(table.getn(nodes), loop_idx - 1,
        "only the peeled iteration is kept")
    test:is(count_irop(nodes, 'LOOP') + count_irop(nodes, 'PHI'), 0,
        "and the markers are gone")

    local unopt = recorded_loop_trace('unopt')
    test:is(table.getn(unroll_at(0, unopt)), table.getn(unopt.trace),
        "the unopt trace is left as one iteration")
end)

test:test("loop unrolling constrains a narrowed IV", function(test)
    test:plan(4)

    local opt = recorded_loop_trace('opt')
    local phis = count_irop(opt.trace, 'PHI')
    test:ok(phis > 0, "the recorded trace has PHI nodes")
    test:is(select(3, unroll_at(2, opt)), '',
        "no op_stack, no constraints")

    local loaded = {}
    local op_stack = {
        load = function(_, ref)
            table.insert(loaded, ref)
            return ('iv_%d'):format(ref)
        end,
    }
    local _, _, smt_out = unroll_at(2, opt, op_stack)

    local constraints = 0
    for _ in smt_out:gmatch('sign_extend 32') do
        constraints = constraints + 1
    end
    test:is(constraints, phis * 3,
        "one wrap constraint per PHI per iteration input")
    test:is(count_duplicates(loaded), 0,
        "each iteration constrains its own refs")
end)

test:test("loop unrolling remaps call arguments", function(test)
    test:plan(3)

    local opt = recorded_loop_trace('opt')
    local nodes = unroll_at(2, opt)
    test:is(count_irop(nodes, 'LOOP') + count_irop(nodes, 'PHI'), 0,
        "no LOOP/PHI left")

    local args = {}
    for _, node in ipairs(nodes) do
        local op1 = node.op1
        if op1 ~= nil and op1.type == 'carg' then
            local first = op1.value[1]
            if first ~= nil and first.tab ~= nil
                and first.tab.type == 'ssa' then
                table.insert(args, first.tab.value)
            end
        end
    end
    test:is(table.getn(args), 3,
        "the peeled call plus one per unrolled iteration")
    test:is(count_duplicates(args), 0,
        "every call reads its own iteration's argument")
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
