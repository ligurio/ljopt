-- In this file we test all known bugs.
--
-- Specifically for this file we have old version of LuaJIT
-- which should generate not equivalent traces.
-- Tests here are similar to tests.lua,
-- but due to requirement of old LuaJIT compiler we extracted
-- them to separate file.

local ffi = require("ffi")
local ljopt = require("ljopt")
local ljopt_config = require("ljopt.config")
local smt = require("tests.smtlib2").new()
local test = require("tests.tap").test("ljopt")
local smt_constants = require('ljopt.smt_constants')
local coverage = require("tests.coverage")
local toggle_debug_hook = require('tests.coverage').toggle_debug_hook()

local buggy_build = os.getenv("BUGGY_BUILD") == "1"
local reproducers_path = coverage.cwd() .. "/tests/reproducers/"

-- Some bugs are reproduced in the DUALNUM mode only (e.g.
-- LuaJIT#1418, LuaJIT#1422), while others rely on the
-- single-number mode (e.g. LuaJIT#783). LuaJIT builds checked by
-- this test can be either in single-number or in DUALNUM mode.
local function is_dualnum_build()
    -- Some LuaJIT versions do not know the `dualnum` ABI flag, so
    -- `ffi.abi("dualnum")` returns false even for a DUALNUM build.
    -- Fall back to a behavioral probe in that case: in a
    -- dual-number build `1 % 1` yields an integer 0 and
    -- `-(1 % 1)` stringifies to "0"; in a single-number build the
    -- result is the double -0.0, which stringifies to "-0".
    local ok, res = pcall(ffi.abi, "dualnum")
    if ok and res then
        return true
    end
    local a = 1 % 1
    return tostring(-a) == "0"
end
local dualnum_build = is_dualnum_build()

-- NOOP when environment variable LJOPT_COVERAGE is undefined.
coverage.enable()

test:plan(30)

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

-- Since not all nodes are implemented we should reset
-- STRICT_MODE here (e.g. for loops can be presented in tests).
ljopt_config.set_strict_mode(false)

-- The function records LuaJIT traces, translate every trace to
-- SMT-LIB formulas, check their SMT-LIB syntax and check that
-- SMT solver returns an expected result for produced formulas.
-- The function returns true if everything was succeed and false
-- otherwise. The function triggers an assertion if no SMT
-- formulas were produced.
-- `force_sat` is for bugs that are still OPEN upstream: the
-- optimised trace diverges from the unoptimised one on every
-- build (no fix exists yet), so ljopt reports SAT regardless of
-- which LuaJIT build records the traces.
local function reproduce_bug_using_smt(chunk, force_sat)
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
        local smt_res = (buggy_build or force_sat)
            and smt.result.SAT or smt.result.UNSAT
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

local function run_shell_command(cmd)
    local _cmd = cmd .. " 2>&1"
    local ph = io.popen(_cmd, "r")
    assert(ph)
    -- The function reads the entire output (both standard output
    -- and standard error) into a single Lua string variable.
    local buffer = ph:read("*a")
    ph:close()
    return buffer
end

local function progname(argv)
    -- arg[-1] is guaranteed to be not nil.
    local idx = -2
    while argv[idx] do
        idx = idx - 1
    end
    return argv[idx + 1]
end

-- Some bugs cannot be reproduced using `pcall()`. In such cases
-- test executes Lua chunk in a separated LuaJIT process.
-- `jit_options` is an optional table of LuaJIT command-line
-- options (e.g. {"-Otryside=1"}) to force the required JIT
-- behavior. The default options are applied first, so options
-- provided by the caller override them.
local function reproduce_bug_in_popen(filename, err_msg, jit_options)
    local options = { "-Ohotloop=1", "-Ohotexit=1" }
    if jit_options ~= nil then
        for _, opt in ipairs(jit_options) do
            options[#options + 1] = opt
        end
    end
    local cmd = ("%s %s %s/tests/reproducers/%s"):format(
        progname(arg), table.concat(options, " "), coverage.cwd(), filename)
    local output = run_shell_command(cmd)
    if buggy_build then
       return string.match(output, err_msg) ~= nil
    end
    return true
end

-- https://github.com/LuaJIT/LuaJIT/pull/783
-- https://github.com/tarantool/luajit/commit/ab0c0793a43fc0fb0c7b71b6250339117d99254a
-- https://github.com/LuaJIT/LuaJIT/commit/7b994e0ee0399caf6319865bbac88ddf62129a36
-- The bug is about the `x - (-0) ==> x` FOLD rule for double
-- operands; it is not reproduced in the DUALNUM mode.
test:test("Fix FOLD rule for x-0 (LuaJIT#783)", function(test)
    test:plan(2)
    if dualnum_build then
        test:skip("reproduce in runtime")
        test:skip("reproduce using SMT")
        return
    end
    local chunk = read_reproducer_file("lj_783.lua")
    test:ok(reproduce_bug_in_runtime(chunk,
        "-0 folding in simplify_numsub_k"), "reproduce in runtime")
    test:ok(reproduce_bug_using_smt(chunk), "reproduce using SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1079
-- https://github.com/LuaJIT/LuaJIT/commit/9e0437240f1fb4bfa7248f6ec8be0e3181016119
-- https://github.com/tarantool/luajit/commit/f0bc08920f1d1b91131bad469f0516fec66e404b
test:test("FFI: Fix 64 bit shift fold rules (LuaJIT#1079)", function(test)
    test:plan(2)
    local chunk = read_reproducer_file("lj_1079.lua")
    test:ok(reproduce_bug_in_runtime(chunk, "folding bitwise rol"),
        "reproduce in runtime")
    test:ok(reproduce_bug_using_smt(chunk), "reproduce using SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1086
test:test("LuaJIT#1086", function(test)
    test:plan(2)
    local chunk = read_reproducer_file("lj_1086.lua")
    local is_reproduced_in_runtime =
        reproduce_bug_in_runtime(chunk, "assertion is violated")
    -- XXX: The bug is reproduced on LuaJIT version without bugs,
    -- see https://github.com/ligurio/ljopt/issues/44.
    if not buggy_build then
        is_reproduced_in_runtime = true
    end
    test:ok(is_reproduced_in_runtime, "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/784
-- https://github.com/tarantool/luajit/commit/804f85a823d619fb25dfbd27da2bb2bb7c22d05e
-- https://github.com/LuaJIT/LuaJIT/commit/e73916d811710ab02a4dfe447d621c99f4e7186c
test:test("Prevent CSE of a REF_BASE operand across IR_RETF (LuaJIT#784)",
function(test)
    test:plan(2)
    local filename = "lj_784.lua"
    test:ok(reproduce_bug_in_popen(filename,
        "no SUB uref REF_BASE CSE across RETF"), "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/791
-- https://github.com/tarantool/luajit/commit/e895818a7ac9c25c8ac07f7b79d89c66bfcefcb2
-- https://github.com/LuaJIT/LuaJIT/commit/bc1bdbf620f58f0978385828bc51272903601e17
test:test("Fix FOLD rule for BUFHDR append (LuaJIT#791)", function(test)
    test:plan(2)
    local chunk = read_reproducer_file("lj_791.lua")
    test:ok(reproduce_bug_in_runtime(chunk, "assertion is violated"),
        "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/792
-- https://github.com/LuaJIT/LuaJIT/commit/d5a237eae03d2ad346f82390836371a952e9a286
-- https://github.com/tarantool/luajit/commit/aed147cd9e40e480c4fe3dc8494a5431727dba87
test:test("Problem of HREFK with table.clear (LuaJIT#792)", function(test)
    test:plan(2)
    local filename = "lj_792.lua"
    -- The reproducer relies on the default hotloop/hotexit
    -- thresholds to hit the exact trace shape.
    test:ok(reproduce_bug_in_popen(filename, "AREF forward from TDUP",
        {"-Ohotloop=56", "-Ohotexit=10"}),
        "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/9
-- https://github.com/LuaJIT/LuaJIT/issues/684
-- https://github.com/LuaJIT/LuaJIT/issues/817
-- https://github.com/tarantool/luajit/commit/203a98682e925d3740291db26184b8a847857943
-- https://github.com/tarantool/luajit/commit/7c959243ab5d10545b33003c71add48b5a6825dc
-- https://github.com/LuaJIT/LuaJIT/commit/96d6d5032098ea9f0002165394a8774dcaa0c0ce
-- https://github.com/LuaJIT/LuaJIT/commit/9512d5c1aced61e13e7be2d3208ec7ae3516b458
test:test("pow() inaccuracy (LuaJIT#817)", function(test)
    test:plan(2)
    -- The `2.0 ^ i ==> ldexp(1.0, i)` divergence is a
    -- JIT-vs-interpreter numeric inaccuracy; it is libm-dependent
    -- and not raised as a Lua error, so there is no runtime
    -- assertion to match. ljopt catches it symbolically instead.
    test:skip("reproduce in runtime")
    local chunk = read_reproducer_file("lj_817.lua")
    test:ok(reproduce_bug_using_smt(chunk), "reproduce using SMT")
end)

-- Incorrect narrowing for huge numbers (LuaJIT#1236).
-- https://github.com/LuaJIT/LuaJIT/issues/1236
-- Still OPEN upstream: narrowing backpropagates an i64
-- conversion across ADD/SUB, but doubles lose integer precision
-- for |x| >= 2^52, so the narrowed trace diverges from the
-- unoptimised one. The divergence surfaces as a Lua `assert`, so
-- it is reproducible in runtime. Because no fix exists yet, ljopt
-- reports SAT on every build (force_sat).
-- Two reproducers from #1236: the plain `s+1-0LL-s` loop and the
-- ffi int64-cast `s+s+s` loop.
test:test("Incorrect narrowing for huge numbers (LuaJIT#1236)",
function(test)
    test:plan(4)
    local err_msg = "incorrect narrowing for huge numbers: "
    local chunk1 = read_reproducer_file("lj_1236.lua")
    test:ok(reproduce_bug_in_popen("lj_1236.lua", err_msg .. "plain loop"),
        "plain `s+1-0LL-s` loop: reproduce in runtime")
    test:ok(reproduce_bug_using_smt(chunk1, true),
        "plain `s+1-0LL-s` loop: reproduce using SMT")
    test:ok(reproduce_bug_in_popen("lj_1236_2.lua",
        err_msg .. "ffi int64 cast loop"),
        "ffi int64-cast `s+s+s` loop: reproduce in runtime")
    -- The ffi variant boxes its result into a cdata whose
    -- trace-local fresh-slot id differs across the two traces, so
    -- the memory-diff disjunct is SAT regardless of value (false
    -- positive), not a genuine narrowing check. This is the
    -- boxed-local identity gap tracked in
    -- https://github.com/ligurio/ljopt/issues/38; until it is fixed
    -- the ffi variant cannot be reproduced via SMT.
    test:skip("ffi int64-cast `s+s+s` loop: reproduce using SMT")
end)

-- Fix FOLD rules for math.abs() and FP negation.
-- https://github.com/LuaJIT/LuaJIT/commit/4416e885d28c0f49d2c7bb3f9630ab23c22fbc9a
-- XXX: This bug cannot be reproduced at runtime (or via SMT) on the
-- pinned LuaJIT builds (buggy 203a~, current af5d38f): the fix
-- (4416e885) is already an ancestor of both. Moreover, the original
-- miscompile depends on the pre-2017 IR representation in which the
-- FP constant operand of NEG/ABS was a true KNUM. In the current IR
-- that constant is loaded via IR_FLOAD REF_NIL, so reverting the fold
-- rules would only disable an optimization instead of producing a
-- wrong result. Hence no reproducer is possible.
test:test("Fix FOLD rules for math.abs() and FP negation", function(test)
    test:plan(2)
    test:skip("reproduce in runtime")
    test:skip("reproduce using SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/994
-- https://github.com/tarantool/luajit/commit/b2548681769604f56bf55cf3d8d8f6a75c44bd1d
-- https://github.com/tarantool/luajit/commit/b89186cb03e79359847cdbeb000a830cc464db35
-- https://github.com/LuaJIT/LuaJIT/commit/a9d183b2be63fd91be4b8c9494c213c56c491092
-- https://github.com/LuaJIT/LuaJIT/commit/9f452bbef5031afc506d8615f5e720c45acd6fdf
test:test(
"Simplify handling of instable types in TNEW/TDUP load forwarding (LuaJIT#994)",
function(test)
    test:plan(2)
    local filename = "lj_994.lua"
    test:ok(reproduce_bug_in_popen(filename,
        "TNEW load forwarding was successful"), "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1133
-- https://github.com/LuaJIT/LuaJIT/commit/658530562c2ac7ffa8e4ca5d18856857471244e9
-- https://github.com/tarantool/luajit/commit/61cef9ec434dd69b7d614ca579a3ffdbb9b333eb
test:test(
"Check for IR_HREF vs. IR_HREFK aliasing in non-nil store check (LuaJIT#1133)",
function(test)
    test:plan(2)
    local filename = "lj_1133.lua"
    test:ok(reproduce_bug_in_popen(filename, "aliasing check is correct"),
        "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1069
-- https://github.com/tarantool/luajit/commit/89f1a82cbdfc6bd285d4a2f6e27f5676f403b526
-- https://github.com/LuaJIT/LuaJIT/commit/7f9907b4ed0870ba64342bcc4b26cff0a94540da
test:test("IR_NEWREF is missing a NaN check (LuaJIT#1069)", function(test)
    test:plan(2)
    local filename = "lj_1069.lua"
    test:ok(reproduce_bug_in_popen(filename, "function returns an error"),
        "reproduce in runtime")
    test:ok(reproduce_bug_using_smt(read_reproducer_file(filename)),
        "reproduce using SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/6163
-- https://github.com/tarantool/luajit/commit/c05d103305da0626e025dbf81370ca9f4f788c83
-- https://github.com/LuaJIT/LuaJIT/commit/03208c8162af9cc01ca76ee1676ca79e5abe9b60
test:test("(LuaJIT#6163)", function(test)
    test:plan(2)
    local filename = "lj_6163.lua"
    -- The reproducer needs the default hotexit threshold (10),
    -- not the forced hotexit=1, to keep the exact trace shape.
    test:ok(reproduce_bug_in_popen(filename, "math.min: comm_dup_minmax",
        {"-Ohotexit=10"}), "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1084
-- https://github.com/LuaJIT/LuaJIT/commit/b8919781d4717d8c3171b0002d230e03304d8174
test:test("Promote 32-bit constants in 64-bit operations (LuaJIT#1084)",
function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_1084.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/299
test:test("GC64: BC_CALLM snapshot handling (LuaJIT#299)", function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_299.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/311
test:test("LuaJIT#311", function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_311.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce using SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/505
-- https://github.com/tarantool/luajit/commit/510b8a1dda5f19df7c5b783b020e51fea5d69abd
test:test("Fold machinery misses data dependency (LuaJIT#505)", function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_505.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/540
test:test("LuaJIT#540", function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_540.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/606
test:test("Fix table bump optimization (LuaJIT#606)", function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_606.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/797
test:test("Missing phi check in bufput_bufstr fold rule (LuaJIT#797)",
function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_797.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1244
-- https://github.com/LuaJIT/LuaJIT/commit/3bdc6498c4c012a8fbf9cfa2756a5b07f56f1540
-- https://github.com/tarantool/luajit/commit/b52fe9795db249e7803aeef22c2ed6129a97aaeb
test:test("Limit CSE for IR_CARG to fix loop optimizations (LuaJIT#1244)",
function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_1244.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/524
-- https://github.com/tarantool/luajit/commit/c9588f51301844d11a2a9dfa9070e437961c9787
test:test("fold: keep type of emitted CONV in sync with its mode (LuaJIT#524)",
function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_524.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/tarantool/luajit/commit/51f722c2dc9b1db3b214a683678e570491fb82d7
-- https://github.com/LuaJIT/LuaJIT/commit/9f0caad0e43f97a4613850b3874b851cb1bc301d
test:test("Fix FOLD rule for strength reduction of widening", function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_fix-fold-simplify-conv-sext.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/commit/c98660c8c3921e43029625e51166c9d273ad09df
-- https://www.freelists.org/post/luajit/bug-in-21-head,3
-- Introduced by
-- https://github.com/LuaJIT/LuaJIT/commit/ccae333844c7aad0934f13f7698894c883a6b561
test:test("Must preserve J->fold.ins (fins) around call to lj_ir_ksimd()",
function(test)
    test:plan(2)
    local _ = read_reproducer_file("lj_ir_ksimd.lua")
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://www.freelists.org/post/luajit/Segmentation-fault-with-JITed-code,1
-- https://github.com/LuaJIT/LuaJIT/commit/a6c34b85f776d8c83b0c01cbdc50550e613d1fda
test:test("Fix ABC elimination in lj_record.c",
function(test)
    test:plan(2)
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://www.freelists.org/post/luajit/Crash-on-lua-code-with-LuaJIT
-- https://github.com/LuaJIT/LuaJIT/commit/6964a7752ae314dcae693abcb0c1175c95ad22e0
test:test("Fix ABC elimination in lj_fold.c",
function(test)
    test:plan(2)
    test:skip("reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/737
-- https://github.com/tarantool/luajit/commit/ca0de768be31f10ccd35569f786a960a76e9fdbb
test:test("Use-def analysis misses slots used by upvalues (LuaJIT#737)",
function(test)
    test:plan(2)
    test:ok(reproduce_bug_in_popen("lj_737.lua", "assertion is violated"),
        "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1128
-- https://github.com/tarantool/luajit/commit/005e8cea3173879bb838fe48e2eb734baca23f0a
test:test("Restore of sunk tables with double IR_NEWREF (LuaJIT#1128)",
function(test)
    test:plan(2)
    test:ok(reproduce_bug_in_popen("lj_1128.lua", "assertion is violated",
        {"-Otryside=1"}), "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1418
-- https://github.com/LuaJIT/LuaJIT/commit/707c12bf00dafdfd3899b1a6c36435dbbf6c7022
-- XXX: The bug is reproduced in the DUALNUM mode only. Runtime
-- reproduction requires a JIT trace to be recorded, hence the
-- `hotloop=1` command-line option.
-- XXX: The `narrow` optimization is supported now (see
-- https://github.com/ligurio/ljopt/issues/34), but SMT reproduction
-- is still not enabled: checking the generated DUALNUM formula hangs
-- cvc5 (verified), so the test stays runtime-only.
test:test(
  "Narrowing of unary minus operation for number 0 in DUALNUM mode \
     (LuaJIT #1418)",
function(test)
    test:plan(4)
    if not dualnum_build then
        test:skip("slot variant: reproduce in runtime")
        test:skip("slot variant: reproduce with SMT")
        test:skip("const variant: reproduce in runtime")
        test:skip("const variant: reproduce with SMT")
        return
    end
    test:ok(reproduce_bug_in_popen("lj_1418_slot.lua", "assertion is violated"),
        "slot variant: reproduce in runtime")
    test:skip("slot variant: reproduce with SMT")
    test:ok(reproduce_bug_in_popen("lj_1418_const.lua",
        "assertion is violated"), "const variant: reproduce in runtime")
    test:skip("const variant: reproduce with SMT")
end)

-- https://github.com/LuaJIT/LuaJIT/issues/1083
-- https://github.com/tarantool/luajit/commit/088e2e161b8aab0ddabc89fb5d9af922536c69f1
-- XXX: reproduced only in the single-number mode.
test:test("Missing coercion when recording select() (LuaJIT#1083)",
function(test)
    test:plan(2)
    if dualnum_build then
        test:skip("reproduce in runtime")
        test:skip("reproduce with SMT")
        return
    end
    test:ok(reproduce_bug_in_popen("lj_1083_select.lua",
        "assertion is violated"),
        "reproduce in runtime")
    test:skip("reproduce with SMT")
end)

coverage.shutdown()

os.exit(test:check() == true and 0 or 1)
