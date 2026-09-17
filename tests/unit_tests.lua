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

test:plan(10)

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
            te_stack = { precondition_refs = {} }
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
    test:is(ctx.te_stack.precondition_refs[2], true,
        "LE on SLOAD-C + const marked")
    test:is(ctx.te_stack.precondition_refs[3], nil,
        "chained LE on non-SLOAD-C operand not marked")

    -- LE whose operand is a stray SSA ref (no SLOAD-C anywhere):
    -- not marked.
    ctx = fresh_ctx()
    ir_passes.mark_narrowed_refs({
        node('LE', 'int', 1, ssa(99), lit('#x7ffffffe')),
    }, ctx)
    test:is(ctx.te_stack.precondition_refs[1], nil,
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

test:test("IR opcode table covers every LuaJIT opcode", function(test)
    test:plan(8)

    local opcodes = require("ljopt.irfuzz.opcodes")
    local opcode_class = require("ljopt.irfuzz.opcode_class")

    local vmdef = require("jit.vmdef")
    local irnames = vmdef.irnames
    local live = {}
    for i = 1, #irnames, 6 do
        live[#live + 1] = (irnames:sub(i, i + 5):gsub("%s+$", ""))
    end

    test:is(#opcodes.ops, #live,
        "opcodes.lua lists every opcode LuaJIT defines")

    local mismatched = {}
    for i, name in ipairs(live) do
        local op = opcodes.ops[i]
        if op == nil or op.name ~= name or op.num ~= i - 1 then
            mismatched[#mismatched + 1] = name
        end
    end
    test:is(table.concat(mismatched, " "), "",
        "opcode names and numbers match jit.vmdef.irnames")

    test:is(table.concat(opcode_class.ops.unclassified, " "), "",
        "every opcode is triaged as emit/const/loop/backend/todo")
    test:is(table.concat(opcode_class.ops.stale, " "), "",
        "no triaged opcode has disappeared from LuaJIT")

    test:is(table.concat(opcode_class.types.unclassified, " "), "",
        "every IRT type is triaged as emit/todo/dead")
    test:is(table.concat(opcode_class.types.stale, " "), "",
        "no triaged IRT type has disappeared from LuaJIT")

    local function runtime_list(t)
        local names = {}
        while t[#names] ~= nil do names[#names + 1] = t[#names] end
        return names
    end
    test:is(#opcodes.fields, #runtime_list(vmdef.irfield),
        "opcodes.lua lists every FLOAD field LuaJIT defines")
    test:is(#opcodes.fpmath, #runtime_list(vmdef.irfpm),
        "opcodes.lua lists every FPMATH mode LuaJIT defines")
end)

test:test("table-driven generator reaches everything it declares",
    function(test)
    test:plan(19)

    local opcodes = require("ljopt.irfuzz.opcodes")
    local opcode_class = require("ljopt.irfuzz.opcode_class")
    local grammar = require("ljopt.irfuzz.grammar")
    local gen_table = require("ljopt.irfuzz.gen_table")

    local bad = {}
    for _, name in ipairs(grammar.covered) do
        if opcode_class.class[name] ~= "emit" then bad[#bad + 1] = name end
    end
    test:is(table.concat(bad, " "), "",
        "every signature is for an emit-class opcode")

    local declared, want = 0, {}
    for _, name in ipairs(grammar.covered) do
        for _, t in ipairs(grammar.sig[name].types) do
            want[name .. ":" .. t] = true
            declared = declared + 1
        end
    end

    local seen = {}
    for seed = 1, 200 do
        local _, hits = gen_table.gen(seed, { insns = 20 })
        for pair in pairs(hits) do seen[pair] = true end
    end
    local unreached = {}
    for pair in pairs(want) do
        if not seen[pair] then unreached[#unreached + 1] = pair end
    end
    table.sort(unreached)
    test:is(table.concat(unreached, " "), "",
        "every declared (opcode, type) pair is emitted within 200 seeds")

    local a = gen_table.gen(7, { insns = 10 })
    local b = gen_table.gen(7, { insns = 10 })
    local same = #a == #b
    for i = 1, #a do
        same = same and a[i].op == b[i].op and a[i].t == b[i].t
            and a[i].ak == b[i].ak and a[i].av == b[i].av
            and a[i].bk == b[i].bk and a[i].bv == b[i].bv
    end
    test:is(same, true, "generation is a pure function of the seed")

    local sload = opcodes.by_name.SLOAD.num
    local known = true
    for _, ins in ipairs(gen_table.gen(3, { insns = 20 })) do
        if ins.op ~= sload then
            known = known and grammar.sig[opcodes.ops[ins.op + 1].name] ~= nil
        end
    end
    test:is(known, true, "every emitted opcode comes from the signature table")

    -- gen.lua's menus carry exclusions IRDEF does not: num MOD and
    -- int DIV/MOD never reach the IR, num POW is modelled
    -- uninterpreted, and MIN/MAX are num-only. Deriving signatures
    -- from IRDEF alone reintroduces every one of them as a false
    -- SAT, so the arithmetic signatures have to stay inside the
    -- menus that knowledge lives in.
    local gen = require("ljopt.irfuzz.gen")
    local arith_universe, allowed = {}, {}
    for _, t in ipairs({ gen.IRT_NUM, gen.IRT_INT }) do
        allowed[t] = {}
        for _, name in ipairs(gen.menu_for(t, true)) do
            allowed[t][name] = true
        end
        for _, name in ipairs(gen.menu_for(t, false)) do
            arith_universe[name] = true
        end
    end

    local outside = {}
    for _, name in ipairs(grammar.covered) do
        for _, t in ipairs(grammar.sig[name].types) do
            if arith_universe[name] and allowed[t] and not allowed[t][name] then
                outside[#outside + 1] = name .. ":" .. t
            end
        end
    end
    table.sort(outside)
    test:is(table.concat(outside, " "), "",
        "no arithmetic signature escapes gen.lua's vetted menus")

    -- `x > x` never holds, so the recorder emits the negated
    -- guard rather than that one, and the two optimization levels
    -- then disagree about the exit. Measured over 40 seeds before
    -- this was forbidden: 7 SAT, all of them spurious.
    local self_cmp = 0
    for seed = 1, 200 do
        for _, ins in ipairs(gen_table.gen(seed, { insns = 14 })) do
            local name = opcodes.ops[ins.op + 1].name
            if (grammar.sig[name] or {}).cmp and ins.ak == grammar.K.REF
                and ins.bk == grammar.K.REF and ins.av == ins.bv then
                self_cmp = self_cmp + 1
            end
        end
    end
    test:is(self_cmp, 0, "no compare guard has both operands the same ref")

    -- The equivalence disjunction reads every compared slot with
    -- get-fp, so an output the recorder could not put in a stack
    -- slot is compared as a float. Measured before this was
    -- restricted: 10 SAT of 40, every one of them spurious.
    local bad_out = {}
    for seed = 1, 100 do
        local insns = gen_table.gen(seed, { insns = 14 })
        for _, ref in ipairs(gen_table.roots(insns)) do
            local t = insns[ref].t % 0x80
            if t ~= grammar.T.NUM and t ~= grammar.T.INT then
                bad_out[#bad_out + 1] = opcodes.types[t + 1]
            end
        end
    end
    test:is(#bad_out, 0, "every compared output is a num or an int")

    -- An ADDOV nothing reads is dead, and DCE drops it together
    -- with the trace exit it carries, which the oracle reads as
    -- the optimized trace skipping an exit. Every overflow op has
    -- to be consumed or compared.
    local dead = 0
    for seed = 1, 100 do
        local insns = gen_table.gen(seed, { insns = 14 })
        local live = {}
        for _, ref in ipairs(gen_table.roots(insns)) do live[ref] = true end
        for _, ins in ipairs(insns) do
            if ins.ak == grammar.K.REF then live[ins.av] = true end
            if ins.bk == grammar.K.REF then live[ins.bv] = true end
        end
        for ref, ins in ipairs(insns) do
            local spec = grammar.sig[opcodes.ops[ins.op + 1].name]
            if spec and spec.guard and not spec.cmp and not spec.novalue
                and not live[ref] then
                dead = dead + 1
            end
        end
    end
    test:is(dead, 0, "no overflow guard is left dead for DCE to remove")

    -- aa_ahref answers a same-ref query from a shortcut and only
    -- reaches its disambiguation path -- different constant keys,
    -- base+-offset, key types -- when two refs differ. With one
    -- AREF per trace that path is unreachable, and injecting a
    -- fault into it was reported as no miscompile at all.
    local both = 0
    for seed = 1, 20 do
        local insns = gen_table.gen(seed, { insns = 12 })
        local keys = { AREF = {}, HREF = {} }
        for _, ins in ipairs(insns) do
            local name = opcodes.ops[ins.op + 1].name
            if keys[name] then keys[name][ins.bv] = true end
        end
        local distinct = 0
        for _, set in pairs(keys) do
            local n = 0
            for _ in pairs(set) do n = n + 1 end
            if n >= 2 then distinct = distinct + 1 end
        end
        if distinct == 2 then both = both + 1 end
    end
    test:is(both, 20,
        "every trace carries two AREFs and two HREFs on distinct keys")

    -- LJFOLD(CALLN KNUM any) constant-folds a math call on a
    -- literal, and ljopt encodes the call as an uninterpreted
    -- function, so the optimized side ends up holding a number the
    -- model cannot equate with it. That is the POW gap; a symbolic
    -- argument fires no fold rule.
    local folded_call, opaque_out = 0, 0
    for seed = 1, 200 do
        local insns = gen_table.gen(seed, { insns = 14 })
        for _, ins in ipairs(insns) do
            local spec = grammar.sig[opcodes.ops[ins.op + 1].name]
            if spec and spec.opaque and ins.ak ~= grammar.K.REF then
                folded_call = folded_call + 1
            end
        end
        for _, ref in ipairs(gen_table.roots(insns)) do
            local spec = grammar.sig[opcodes.ops[insns[ref].op + 1].name]
            if spec and spec.opaque then opaque_out = opaque_out + 1 end
        end
    end
    test:is(folded_call, 0, "no uninterpreted call takes a constant argument")
    test:is(opaque_out, 0, "no uninterpreted result is compared as an output")

    -- An FLOAD reads a field of a specific object: tab.array and
    -- tab.asize off a table, cdata.int64 off a cdata. Pairing a
    -- producer with its consumer used to pass NONE as the field,
    -- which reads as field 0 -- a string's length taken off a
    -- table. The two sides agree on that, so the oracle never
    -- reports it; only this check does.
    local mistyped = 0
    for seed = 1, 200 do
        local insns = gen_table.gen(seed, { insns = 14 })
        local ty = {}
        for ref, ins in ipairs(insns) do
            ty[ref] = ins.t % 0x80
            local spec = grammar.sig[opcodes.ops[ins.op + 1].name]
            if spec and spec.field_of then
                local want = spec.op1_of and spec.op1_of[ty[ref]]
                local ok = ins.bk == grammar.K.LIT
                    and ins.bv == spec.field_of[ty[ref]]
                if want then
                    local match = false
                    for _, w in ipairs(want) do
                        if ty[ins.av] == w then match = true end
                    end
                    ok = ok and match
                end
                if not ok then mistyped = mistyped + 1 end
            end
        end
    end
    test:is(mistyped, 0, "every field load names the field its type selects")

    -- Malformed IR that both levels agree on is invisible to the
    -- oracle: the two sides encode it identically and it compares
    -- equal. Checking every emitted instruction against the
    -- signature it came from is the only thing that finds it --
    -- that is how the TNEW pairing emitting a NONE field, read as
    -- str.len off a table, was caught.
    local violations = {}
    local function note(what)
        if #violations < 5 then violations[#violations + 1] = what end
    end
    for seed = 1, 100 do
        local insns, _, nprologue = gen_table.gen(seed, { insns = 14 })
        local ty = {}
        for ref, ins in ipairs(insns) do
            local name = opcodes.ops[ins.op + 1].name
            local t = ins.t % 0x80
            ty[ref] = t
            local spec = ref > nprologue and grammar.sig[name] or nil
            if spec then
                local allowed = false
                for _, x in ipairs(spec.types) do
                    if x == t then allowed = true end
                end
                if not allowed then note(name .. " at type " .. t) end
            end
            -- Every reference has to point backwards, at an
            -- instruction that already exists.
            if ins.ak == grammar.K.REF and not (ins.av < ref) then
                note(name .. " op1 references " .. ins.av)
            end
            if ins.bk == grammar.K.REF and not (ins.bv < ref) then
                note(name .. " op2 references " .. ins.bv)
            end
            -- A `from` constraint names the opcode that must have
            -- produced the operand.
            if spec and spec.op1 and spec.op1.from
                and ins.ak == grammar.K.REF then
                local src = opcodes.ops[insns[ins.av].op + 1].name
                if not spec.op1.from[src] then
                    note(name .. " op1 produced by " .. src)
                end
            end
        end
    end
    test:is(table.concat(violations, "; "), "",
        "every emitted instruction matches the signature it came from")

    -- LJFOLD(ADDOV any KINT) drops the overflow check when that
    -- operand is 0, and the optimized trace then has one exit
    -- fewer. A reference is not safe either: seed 603 reached the
    -- rule through `x ^ x`, which folds to 0.
    local zeroable = 0
    for seed = 1, 200 do
        for _, ins in ipairs(gen_table.gen(seed, { insns = 14 })) do
            local spec = grammar.sig[opcodes.ops[ins.op + 1].name]
            if spec and spec.ovf
                and (ins.bk ~= grammar.K.KINT or ins.bv == 0) then
                zeroable = zeroable + 1
            end
        end
    end
    test:is(zeroable, 0,
        "every overflow guard has a non-zero constant operand")

    -- The two FFI addresses have to differ, or CSE leaves the two
    -- sides holding a different number of ADDs; and they have to
    -- be able to land at least one access width apart, or aa_xref
    -- never reaches its non-overlapping answer. Enforcing only the
    -- first by taking adjacent pool entries silently removed the
    -- second, and the fault aimed at that branch went quiet.
    local identical, disjoint = 0, 0
    for seed = 1, 200 do
        local insns = gen_table.gen(seed, { insns = 12 })
        local ofs = {}
        for _, ins in ipairs(insns) do
            if opcodes.ops[ins.op + 1].name == "ADD"
                and ins.t % 0x80 == grammar.T.P64 then
                ofs[#ofs + 1] = ins.bv
            end
        end
        if #ofs == 2 then
            if ofs[1] == ofs[2] then identical = identical + 1 end
            if math.abs(ofs[1] - ofs[2]) >= 4 then disjoint = disjoint + 1 end
        end
    end
    test:is(identical, 0, "the two FFI addresses are never the same offset")
    test:ok(disjoint > 0,
        "some FFI address pairs are disjoint for a 4-byte access")

    -- A loop replay writes output k back into the slot SLOAD k
    -- reads, so nothing is carried unless an output has that
    -- slot's type. Without a value per input slot most traces are
    -- checked as straight-line while the run is reported as
    -- covering loops: 5 of 12 formed no PHI at all.
    local uncarried = 0
    for seed = 1, 50 do
        local insns = gen_table.gen(seed, { insns = 12, loop = true })
        local have = {}
        for _, ref in ipairs(gen_table.roots(insns)) do
            have[insns[ref].t % 0x80] = true
        end
        for slot = 1, 3 do
            if not have[insns[slot].t % 0x80] then
                uncarried = uncarried + 1
            end
        end
    end
    test:is(uncarried, 0,
        "loop mode leaves every input slot a value of its own type")

    -- A loop's state lives in stack slots, so its body stays on
    -- the types a slot can hold. Dropping the table, upvalue and
    -- cdata roots does not achieve that by itself -- TNEW
    -- allocates a table inside the body and HREF follows it back
    -- in, which crashed the unroller on seed 51786 and, before
    -- that, reported two miscompiles that were not.
    local VALUE = { [grammar.T.NUM] = true, [grammar.T.INT] = true,
                    [grammar.T.I64] = true }
    local offenders = {}
    for seed = 1, 100 do
        for _, ins in ipairs(gen_table.gen(seed, { insns = 8, loop = true })) do
            local name = opcodes.ops[ins.op + 1].name
            if name ~= "SLOAD" and not VALUE[ins.t % 0x80]
                and #offenders < 4 then
                offenders[#offenders + 1] = name
            end
        end
    end
    test:is(table.concat(offenders, " "), "",
        "a loop body holds only values a stack slot can carry")

    -- Two reads of one slot at the same type are a single
    -- instruction after CSE, and at different types they
    -- contradict each other, so every SLOAD takes a slot nothing
    -- else has claimed.
    local reused = 0
    for seed = 1, 100 do
        local used = {}
        for _, ins in ipairs(gen_table.gen(seed, { insns = 14 })) do
            if opcodes.ops[ins.op + 1].name == "SLOAD" then
                if used[ins.av] then reused = reused + 1 end
                used[ins.av] = true
            end
        end
    end
    test:is(reused, 0, "every SLOAD reads a slot of its own")
end)

require("tests.coverage").shutdown()

os.exit(test:check() == true and 0 or 1)
