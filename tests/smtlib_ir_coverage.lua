--[[
smtlib_ir_coverage.lua

A single Lua chunk that exercises as many LuaJIT IR
instructions as possible so that ljopt's SMT-LIB
translator (ljopt/ir/*.lua) is covered when this file
is translated.

Usage:
    LUA_PATH="./?/init.lua;;" bin/ljopt \
        tests/smtlib_ir_coverage.lua > out.smt2
    z3 -smt2 out.smt2
    cvc5 --lang smt2 out.smt2

ljopt records the chunk twice (JIT optimisations off and
on) and translates every matched trace to SMT-LIB.  Only
the part of a trace up to its first LOOP instruction is
translated, so the file is made of small "flat" functions
(each becomes a LOOP-less root trace that is translated
in full) plus a few loops whose peeled body carries the
loop-header instructions (int SLOAD, int guards, int MOD).

Important structural rules that keep the recorded traces
translatable:

  * every operation family lives in its own function, and
    each such function is called through explicit repeated
    top-level calls, NOT inside a `for` loop: a traced
    wrapper loop folds each callee to a constant and ljopt
    then trips over a constant-backed FLOAD func.env
    (constant tables are not implemented);
  * a `jit.flush()` is emitted between the call groups so
    every function is recorded independently, like the
    single-function chunks in tests/tests.lua.  (Which hot
    functions LuaJIT actually turns into traces can vary
    slightly from run to run, so the exact set of emitted
    traces is not fixed; every emitted trace must
    nonetheless parse with both solvers.)
  * every computed value is kept "live" (flows into a
    returned value or stored state), otherwise the JIT's
    DCE removes the instruction;
  * FFI cell pointers are passed as function arguments, and
    literal int64 operands in arithmetic on raw FFI memory
    are avoided: ljopt cannot yet retrieve an i64 literal
    operand there.

NOTE: a few translator instances cannot be produced from
Lua source and are only reachable through hand-built IR
nodes (tests/ir_tests.lua): int MUL / MULOV / DIV, i64
ABS, CONV int.u32 / int.u8 / num.u64 / u32.int / i64.u32,
FPMATH trunc, NE i64, p64 ADD on strings, num MOD (Lua
lowers `x % y` into DIV + FPMATH + MUL + SUB).  They are
intentionally not attempted here.
]]

local ffi = require("ffi")
local bit = require("bit")

------------------------------------------------------------------
-- 1. Floating-point arithmetic, FPMATH and CALLN.
------------------------------------------------------------------
local function fn_num_arith(x)
    return x + 0.23, x - 0.23, x * 0.23, x / 0.23, -x,
           math.abs(x)
end

-- floor / ceil (FPMATH). math.modf is avoided: it triggers trace
-- stitching (see tests.lua "Stitching test").
local function fn_fpmath(x)
    return math.floor(x), math.ceil(x)
end

local function fn_sqrt(x)
    return math.sqrt(x)
end

local function fn_log(x)
    return math.log(x)
end

local function fn_log10(x)
    return math.log10(x)
end

-- math.* that lower to CALLN (uninterpreted per function).
local function fn_calln(x)
    return math.exp(x), math.sin(x), math.cos(x), math.tan(x),
           math.sinh(x), math.cosh(x), math.tanh(x), math.asin(x),
           math.acos(x), math.atan(x)
end

local function fn_atan2(x)
    return math.atan2(x, 0.5)
end

local function fn_pow_ldexp_minmax(x)
    return 2.0 ^ x, math.ldexp(x, 2), math.min(x, 1.5), math.max(x, 1.5)
end

------------------------------------------------------------------
-- 2. Floating-point guarded comparisons.
-- A single function covers both taken and not-taken guards;
-- the exact opcode depends on operand order and sign, so both
-- operand orders are provided (optimisations off/on also yield
-- complementary opcodes).
------------------------------------------------------------------
local function fn_cmp_num(a, b)
    local r = 0
    if a < b then r = r + 1 end
    if a > b then r = r + 1 end
    if a <= b then r = r + 1 end
    if a >= b then r = r + 1 end
    if a == b then r = r + 1 end
    if a ~= b then r = r + 1 end
    return r
end

local function fn_cmp_num_swapped(a, b)
    local r = 0
    if b < a then r = r + 1 end
    if b > a then r = r + 1 end
    if b <= a then r = r + 1 end
    if b >= a then r = r + 1 end
    return r
end

-- EQ on numbers: a memory-derived value compared against a slot.
local function fn_eq_num(x)
    local t = { x }
    local r = 0
    if t[1] == x then r = r + 1 end
    return r
end

------------------------------------------------------------------
-- 3. Integer arithmetic and guarded comparisons.
------------------------------------------------------------------
local function fn_int_arith(a, b)
    local x = bit.band(a, 0xffff)
    local y = bit.band(b, 0xffff)
    local r = x + y
    r = r + (x - y)
    r = r + (x * y)
    if x < y then r = r + 1 end
    if x > y then r = r + 1 end
    if x <= y then r = r + 1 end
    if x >= y then r = r + 1 end
    if x == y then r = r + 1 end
    if x ~= y then r = r + 1 end
    return r
end

local function fn_int_minmax(a, b)
    local x = bit.band(a, 0xffff)
    local y = bit.band(b, 0xffff)
    return math.min(x, y), math.max(x, y)
end

local function fn_eq_int(a)
    local x = bit.band(a, 0xffff)
    local r = 0
    if x == 12 then r = r + 1 end
    if x ~= 12 then r = r + 1 end
    return r
end

-- int guards from a runtime-bounded loop (counter is int).
local function fn_loop_int_guards(n)
    local r = 0
    for i = 1, n do
        if i < n then r = r + 1 end
        if i > 2 then r = r + 1 end
        if i <= n then r = r + 1 end
        if i >= 2 then r = r + 1 end
        if i == n then r = r + 1 end
        if i ~= n then r = r + 1 end
    end
    return r
end

-- int MOD (loop counter is provably int32).
local function fn_loop_int_mod(n)
    local r = 0
    for i = 1, n do
        r = r + i % 7
    end
    return r
end

------------------------------------------------------------------
-- 4. Bit operations (int and i64).
------------------------------------------------------------------
local function fn_bit_int(x)
    local j = bit.band(x, 0xffff)
    return bit.bnot(j), bit.bor(j, 1), bit.bxor(j, 1),
           bit.lshift(j, 2), bit.rshift(j, 2), bit.arshift(j, 2),
           bit.rol(j, 2), bit.ror(j, 2), bit.bswap(j), bit.tobit(j * 3)
end

local function fn_bit_i64(i)
    local a = 0xaaLL
    local b = i * 1LL
    return tonumber(bit.band(a, b)), tonumber(bit.bor(a, b)),
           tonumber(bit.bxor(a, b)), tonumber(bit.bnot(a)),
           tonumber(bit.lshift(a, 2)), tonumber(bit.rshift(a, 2)),
           tonumber(bit.arshift(a, 2)), tonumber(bit.rol(a, 2)),
           tonumber(bit.ror(a, 2))
end

------------------------------------------------------------------
-- 5. i64 arithmetic.
------------------------------------------------------------------
local function fn_i64_arith(i)
    local a = 23LL
    local b = i * 1LL
    return tonumber(a + b), tonumber(a - b), tonumber(a * b),
           tonumber(a / b), tonumber(a % b)
end

local function fn_i64_eq(a, b)
    local r = 0
    if a == b then r = r + 1 end
    return r
end

------------------------------------------------------------------
-- 6. Tables: TNEW, HREFK/HREF, HSTORE/HLOAD, NEWREF, AREF,
--    ALOAD/ASTORE.
------------------------------------------------------------------
local t_hash = {}
local function fn_tab_hash(x)
    t_hash["key"] = x
    local v = t_hash["key"]
    t_hash["s"] = "str"
    local sv = t_hash["s"]
    t_hash["t"] = {}
    local tv = t_hash["t"]
    t_hash["b"] = false
    t_hash["d"] = nil
    return v, sv, tv
end

-- A table with a large hash part makes the key access a plain
-- HREF.
local big = {}
for k = 1, 4096 do big["k" .. k] = k end
local function fn_tab_href(x)
    big["mykey"] = x
    return big["mykey"]
end

local empty = {}
local function fn_tab_newref(x)
    empty["a"] = x
    return empty["a"]
end

local arr = {}
local function fn_tab_arr()
    arr[1] = 10
    local v = arr[1]
    arr[2] = "str"
    local s = arr[2]
    arr[3] = false
    arr[4] = nil
    return v, s
end

local tbl_of_tabs = {}
local function fn_tab_aref_load(x)
    local inner = { 1.0, x }
    tbl_of_tabs[1] = inner
    local u = tbl_of_tabs[1]
    return u[2]
end

------------------------------------------------------------------
-- 7. Loads / stores of scalars and table fields.
------------------------------------------------------------------
local function fn_str_len(s)
    return #s
end

local function fn_setmeta()
    local mt = { __index = { x = 42 } }
    local t = {}
    setmetatable(t, mt)
    return t.x
end

-- 8. Raw FFI memory: XLOAD / XSTORE of all widths.
-- The pointers are passed as arguments (not upvalues): ljopt
-- cannot yet translate address arithmetic over a constant cdata
-- base (it trips over an i64 literal stride operand).  Literal
-- i64 operands in raw-memory arithmetic are likewise avoided.
------------------------------------------------------------------
local dcell = ffi.new("double[1]", 1.5)
local icell = ffi.new("int[1]", 42)
local i64cell = ffi.new("int64_t[1]", 42)
local i64cell2 = ffi.new("int64_t[1]", 2)
local fcell = ffi.new("float[1]", 1.5)
local u32cell = ffi.new("uint32_t[1]", 7)

local function fn_xmem(d, i, i64, i64b, f, u)
    local a = d[0]
    d[0] = a + 1.0
    local b = i[0]
    i[0] = b + 1
    local c = i64[0]
    local c2 = i64b[0]
    i64[0] = c + c2
    local e = f[0]
    f[0] = e + 1.5
    local g = u[0]
    u[0] = g + 1
    return a, b, c, e, g
end

------------------------------------------------------------------
-- 9. Allocations: CNEW (VLA), CNEWI, TNEW, and CALLXS.
------------------------------------------------------------------
ffi.cdef[[
int abs(int x);
long long llabs(long long x);
]]

local function fn_cnew()
    local vla = ffi.typeof("uint8_t[?]")
    local p = vla(1)
    p[0] = 7
    return p[0]
end

local function fn_cnewi(x)
    local v = ffi.new("int64_t", x)
    local cell = ffi.new("int64_t[1]")
    cell[0] = v
    return cell[0]
end

local function fn_callxs_int(i)
    return ffi.C.abs(-i)
end

local function fn_callxs_i64(i)
    return tonumber(ffi.C.llabs(-i * 1LL))
end

------------------------------------------------------------------
-- 10. Strings: BUFHDR/BUFPUT/BUFSTR, CALLL, TOSTR, STRTO.
------------------------------------------------------------------
local function fn_str_concat(a, b)
    return a .. b
end

local function fn_str_reverse(s)
    return string.reverse(s)
end

local function fn_tostr_int(i)
    return tostring(i)
end

local function fn_tostr_num(x)
    return tostring(x)
end

local function fn_tostr_char(i)
    return string.char(i)
end

local function fn_strto(s)
    return tonumber(s)
end

------------------------------------------------------------------
-- 11. CONV modes.
------------------------------------------------------------------
local function fn_conv_num_int(i)
    -- int -> num (num.int): store an int into a numeric slot.
    local t = {}
    t[1] = i
    return t[1]
end

local function fn_conv_int_num(x)
    -- num -> int (int.num): float used as a table index.
    local t = {}
    t[math.floor(x)] = 1
    return t[math.floor(x)]
end

local function fn_conv_i64_num(i)
    -- i64 -> num (num.i64).
    return tonumber(i * 2LL)
end

local function fn_conv_num_i64(x)
    -- num -> i64 (i64.num).
    local v = ffi.new("int64_t", x)
    return v
end

local function fn_conv_u64_num(x)
    -- num -> u64 (u64.num).
    local v = ffi.new("uint64_t", x)
    return v
end

local function fn_conv_i64_int(i)
    -- int -> i64 (i64.int, sign-extended when needed).
    local v = ffi.new("int64_t", i)
    return v
end

local function fn_conv_int_i64(v)
    -- i64 -> int (int.i64): cast of a 64-bit value to 32 bits.
    local cell = ffi.new("int64_t[1]", v)
    return tonumber(ffi.cast("int32_t", cell[0]))
end

local function fn_conv_u64_int(i)
    -- int -> u64 (u64.int).
    local x = bit.band(i, 0xffff)
    local v = ffi.new("uint64_t", x)
    return v
end

local function fn_conv_u32(x)
    -- num -> u32 (u32.num) and u32 -> num (num.u32).
    local v = ffi.new("uint32_t", x)
    return tonumber(v), v
end

local function fn_conv_flt(x)
    -- num -> flt / flt -> num through a float field.
    local st = ffi.typeof("struct { float a; }")
    local y = st(x)
    local v = y.a
    y.a = v + 1.5
    return y.a
end

-- u8 -> int (int.u8): not exercised here -- it needs a traced
-- ffi.fill loop whose byte stores ljopt cannot yet translate (u8
-- XSTORE/XLOAD are NYI).  It is covered by tests/tests.lua.

------------------------------------------------------------------
-- 12. u32 guards.
------------------------------------------------------------------
local function fn_u32_cmp(x, y)
    local a = ffi.new("uint32_t", x)
    local b = ffi.new("uint32_t", y)
    local r = 0
    if a == b then r = r + 1 end
    if a ~= b then r = r + 1 end
    if a < b then r = r + 1 end
    if a > b then r = r + 1 end
    if a <= b then r = r + 1 end
    if a >= b then r = r + 1 end
    return r
end

------------------------------------------------------------------
-- Everything below must stay unrolled: a `for` wrapper loop
-- would be traced itself and fold the callees to constants,
-- producing traces that ljopt cannot translate.
------------------------------------------------------------------
jit.flush()
fn_num_arith(1.3); fn_num_arith(1.3); fn_num_arith(1.3)
fn_num_arith(1.3); fn_num_arith(1.3); fn_num_arith(1.3)
fn_num_arith(1.3); fn_num_arith(1.3); fn_num_arith(1.3)
fn_num_arith(1.3); fn_num_arith(1.3); fn_num_arith(1.3)

jit.flush()
fn_fpmath(1.3); fn_fpmath(1.3); fn_fpmath(1.3)
fn_fpmath(1.3); fn_fpmath(1.3); fn_fpmath(1.3)
fn_fpmath(1.3); fn_fpmath(1.3); fn_fpmath(1.3)
fn_fpmath(1.3); fn_fpmath(1.3); fn_fpmath(1.3)

jit.flush()
fn_sqrt(1.3); fn_sqrt(1.3); fn_sqrt(1.3); fn_sqrt(1.3)
fn_sqrt(1.3); fn_sqrt(1.3); fn_sqrt(1.3); fn_sqrt(1.3)
fn_sqrt(1.3); fn_sqrt(1.3); fn_sqrt(1.3); fn_sqrt(1.3)

jit.flush()
fn_log(1.3); fn_log(1.3); fn_log(1.3); fn_log(1.3)
fn_log(1.3); fn_log(1.3); fn_log(1.3); fn_log(1.3)
fn_log(1.3); fn_log(1.3); fn_log(1.3); fn_log(1.3)

jit.flush()
fn_log10(1.3); fn_log10(1.3); fn_log10(1.3); fn_log10(1.3)
fn_log10(1.3); fn_log10(1.3); fn_log10(1.3); fn_log10(1.3)
fn_log10(1.3); fn_log10(1.3); fn_log10(1.3); fn_log10(1.3)

jit.flush()
fn_calln(0.5); fn_calln(0.5); fn_calln(0.5); fn_calln(0.5)
fn_calln(0.5); fn_calln(0.5); fn_calln(0.5); fn_calln(0.5)
fn_calln(0.5); fn_calln(0.5); fn_calln(0.5); fn_calln(0.5)

jit.flush()
fn_atan2(0.5); fn_atan2(0.5); fn_atan2(0.5); fn_atan2(0.5)
fn_atan2(0.5); fn_atan2(0.5); fn_atan2(0.5); fn_atan2(0.5)
fn_atan2(0.5); fn_atan2(0.5); fn_atan2(0.5); fn_atan2(0.5)

jit.flush()
fn_pow_ldexp_minmax(1.3); fn_pow_ldexp_minmax(1.3); fn_pow_ldexp_minmax(1.3)
fn_pow_ldexp_minmax(1.3); fn_pow_ldexp_minmax(1.3); fn_pow_ldexp_minmax(1.3)
fn_pow_ldexp_minmax(1.3); fn_pow_ldexp_minmax(1.3); fn_pow_ldexp_minmax(1.3)
fn_pow_ldexp_minmax(1.3); fn_pow_ldexp_minmax(1.3); fn_pow_ldexp_minmax(1.3)

jit.flush()
fn_cmp_num(1.5, 2.5); fn_cmp_num(1.5, 2.5); fn_cmp_num(1.5, 2.5)
fn_cmp_num(1.5, 2.5); fn_cmp_num(1.5, 2.5); fn_cmp_num(1.5, 2.5)
fn_cmp_num(1.5, 2.5); fn_cmp_num(1.5, 2.5); fn_cmp_num(1.5, 2.5)
fn_cmp_num(1.5, 2.5); fn_cmp_num(1.5, 2.5); fn_cmp_num(1.5, 2.5)

jit.flush()
fn_cmp_num_swapped(1.5, 2.5); fn_cmp_num_swapped(1.5, 2.5)
fn_cmp_num_swapped(1.5, 2.5); fn_cmp_num_swapped(1.5, 2.5)
fn_cmp_num_swapped(1.5, 2.5); fn_cmp_num_swapped(1.5, 2.5)
fn_cmp_num_swapped(1.5, 2.5); fn_cmp_num_swapped(1.5, 2.5)
fn_cmp_num_swapped(1.5, 2.5); fn_cmp_num_swapped(1.5, 2.5)
fn_cmp_num_swapped(1.5, 2.5); fn_cmp_num_swapped(1.5, 2.5)

jit.flush()
fn_eq_num(2.5); fn_eq_num(2.5); fn_eq_num(2.5); fn_eq_num(2.5)
fn_eq_num(2.5); fn_eq_num(2.5); fn_eq_num(2.5); fn_eq_num(2.5)
fn_eq_num(2.5); fn_eq_num(2.5); fn_eq_num(2.5); fn_eq_num(2.5)

jit.flush()
fn_int_arith(13, 29); fn_int_arith(13, 29); fn_int_arith(13, 29)
fn_int_arith(13, 29); fn_int_arith(13, 29); fn_int_arith(13, 29)
fn_int_arith(13, 29); fn_int_arith(13, 29); fn_int_arith(13, 29)
fn_int_arith(13, 29); fn_int_arith(13, 29); fn_int_arith(13, 29)

jit.flush()
fn_int_minmax(13, 29); fn_int_minmax(13, 29); fn_int_minmax(13, 29)
fn_int_minmax(13, 29); fn_int_minmax(13, 29); fn_int_minmax(13, 29)
fn_int_minmax(13, 29); fn_int_minmax(13, 29); fn_int_minmax(13, 29)
fn_int_minmax(13, 29); fn_int_minmax(13, 29); fn_int_minmax(13, 29)

jit.flush()
fn_eq_int(12); fn_eq_int(12); fn_eq_int(12); fn_eq_int(12)
fn_eq_int(12); fn_eq_int(12); fn_eq_int(12); fn_eq_int(12)
fn_eq_int(12); fn_eq_int(12); fn_eq_int(12); fn_eq_int(12)

jit.flush()
fn_loop_int_guards(300); fn_loop_int_guards(300); fn_loop_int_guards(300)
fn_loop_int_guards(300); fn_loop_int_guards(300); fn_loop_int_guards(300)
fn_loop_int_guards(300); fn_loop_int_guards(300); fn_loop_int_guards(300)

jit.flush()
fn_loop_int_mod(300); fn_loop_int_mod(300); fn_loop_int_mod(300)
fn_loop_int_mod(300); fn_loop_int_mod(300); fn_loop_int_mod(300)
fn_loop_int_mod(300); fn_loop_int_mod(300); fn_loop_int_mod(300)

jit.flush()
fn_bit_int(13); fn_bit_int(13); fn_bit_int(13); fn_bit_int(13)
fn_bit_int(13); fn_bit_int(13); fn_bit_int(13); fn_bit_int(13)
fn_bit_int(13); fn_bit_int(13); fn_bit_int(13); fn_bit_int(13)

jit.flush()
fn_bit_i64(7); fn_bit_i64(7); fn_bit_i64(7); fn_bit_i64(7)
fn_bit_i64(7); fn_bit_i64(7); fn_bit_i64(7); fn_bit_i64(7)
fn_bit_i64(7); fn_bit_i64(7); fn_bit_i64(7); fn_bit_i64(7)

jit.flush()
fn_i64_arith(7); fn_i64_arith(7); fn_i64_arith(7); fn_i64_arith(7)
fn_i64_arith(7); fn_i64_arith(7); fn_i64_arith(7); fn_i64_arith(7)
fn_i64_arith(7); fn_i64_arith(7); fn_i64_arith(7); fn_i64_arith(7)

jit.flush()
fn_i64_eq(5LL, 5LL); fn_i64_eq(5LL, 5LL); fn_i64_eq(5LL, 5LL)
fn_i64_eq(5LL, 5LL); fn_i64_eq(5LL, 5LL); fn_i64_eq(5LL, 5LL)
fn_i64_eq(5LL, 5LL); fn_i64_eq(5LL, 5LL); fn_i64_eq(5LL, 5LL)
fn_i64_eq(5LL, 5LL); fn_i64_eq(5LL, 5LL); fn_i64_eq(5LL, 5LL)

jit.flush()
fn_tab_hash(1.5); fn_tab_hash(1.5); fn_tab_hash(1.5); fn_tab_hash(1.5)
fn_tab_hash(1.5); fn_tab_hash(1.5); fn_tab_hash(1.5); fn_tab_hash(1.5)
fn_tab_hash(1.5); fn_tab_hash(1.5); fn_tab_hash(1.5); fn_tab_hash(1.5)

jit.flush()
fn_tab_href(0.42); fn_tab_href(0.42); fn_tab_href(0.42); fn_tab_href(0.42)
fn_tab_href(0.42); fn_tab_href(0.42); fn_tab_href(0.42); fn_tab_href(0.42)
fn_tab_href(0.42); fn_tab_href(0.42); fn_tab_href(0.42); fn_tab_href(0.42)

jit.flush()
fn_tab_newref(1.5); fn_tab_newref(1.5); fn_tab_newref(1.5); fn_tab_newref(1.5)
fn_tab_newref(1.5); fn_tab_newref(1.5); fn_tab_newref(1.5); fn_tab_newref(1.5)
fn_tab_newref(1.5); fn_tab_newref(1.5); fn_tab_newref(1.5); fn_tab_newref(1.5)

jit.flush()
fn_tab_arr(); fn_tab_arr(); fn_tab_arr(); fn_tab_arr()
fn_tab_arr(); fn_tab_arr(); fn_tab_arr(); fn_tab_arr()
fn_tab_arr(); fn_tab_arr(); fn_tab_arr(); fn_tab_arr()

jit.flush()
fn_tab_aref_load(2.5); fn_tab_aref_load(2.5); fn_tab_aref_load(2.5)
fn_tab_aref_load(2.5); fn_tab_aref_load(2.5); fn_tab_aref_load(2.5)
fn_tab_aref_load(2.5); fn_tab_aref_load(2.5); fn_tab_aref_load(2.5)
fn_tab_aref_load(2.5); fn_tab_aref_load(2.5); fn_tab_aref_load(2.5)

jit.flush()
fn_str_len("hello world!"); fn_str_len("hello world!")
fn_str_len("hello world!")
fn_str_len("hello world!"); fn_str_len("hello world!")
fn_str_len("hello world!")
fn_str_len("hello world!"); fn_str_len("hello world!")
fn_str_len("hello world!")
fn_str_len("hello world!"); fn_str_len("hello world!")
fn_str_len("hello world!")

jit.flush()
fn_setmeta(); fn_setmeta(); fn_setmeta(); fn_setmeta()
fn_setmeta(); fn_setmeta(); fn_setmeta(); fn_setmeta()
fn_setmeta(); fn_setmeta(); fn_setmeta(); fn_setmeta()

jit.flush()
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)
fn_xmem(dcell, icell, i64cell, i64cell2, fcell, u32cell)

jit.flush()
fn_cnew(); fn_cnew(); fn_cnew(); fn_cnew()
fn_cnew(); fn_cnew(); fn_cnew(); fn_cnew()
fn_cnew(); fn_cnew(); fn_cnew(); fn_cnew()

jit.flush()
fn_cnewi(5); fn_cnewi(5); fn_cnewi(5); fn_cnewi(5)
fn_cnewi(5); fn_cnewi(5); fn_cnewi(5); fn_cnewi(5)
fn_cnewi(5); fn_cnewi(5); fn_cnewi(5); fn_cnewi(5)

jit.flush()
fn_callxs_int(13); fn_callxs_int(13); fn_callxs_int(13); fn_callxs_int(13)
fn_callxs_int(13); fn_callxs_int(13); fn_callxs_int(13); fn_callxs_int(13)
fn_callxs_int(13); fn_callxs_int(13); fn_callxs_int(13); fn_callxs_int(13)

jit.flush()
fn_callxs_i64(13); fn_callxs_i64(13); fn_callxs_i64(13); fn_callxs_i64(13)
fn_callxs_i64(13); fn_callxs_i64(13); fn_callxs_i64(13); fn_callxs_i64(13)
fn_callxs_i64(13); fn_callxs_i64(13); fn_callxs_i64(13); fn_callxs_i64(13)

jit.flush()
fn_str_concat("foo", "bar"); fn_str_concat("foo", "bar")
fn_str_concat("foo", "bar"); fn_str_concat("foo", "bar")
fn_str_concat("foo", "bar"); fn_str_concat("foo", "bar")
fn_str_concat("foo", "bar"); fn_str_concat("foo", "bar")
fn_str_concat("foo", "bar"); fn_str_concat("foo", "bar")
fn_str_concat("foo", "bar"); fn_str_concat("foo", "bar")

jit.flush()
fn_str_reverse("asdf"); fn_str_reverse("asdf"); fn_str_reverse("asdf")
fn_str_reverse("asdf"); fn_str_reverse("asdf"); fn_str_reverse("asdf")
fn_str_reverse("asdf"); fn_str_reverse("asdf"); fn_str_reverse("asdf")
fn_str_reverse("asdf"); fn_str_reverse("asdf"); fn_str_reverse("asdf")

jit.flush()
fn_tostr_int(7); fn_tostr_int(7); fn_tostr_int(7); fn_tostr_int(7)
fn_tostr_int(7); fn_tostr_int(7); fn_tostr_int(7); fn_tostr_int(7)
fn_tostr_int(7); fn_tostr_int(7); fn_tostr_int(7); fn_tostr_int(7)

jit.flush()
fn_tostr_num(1.25); fn_tostr_num(1.25); fn_tostr_num(1.25); fn_tostr_num(1.25)
fn_tostr_num(1.25); fn_tostr_num(1.25); fn_tostr_num(1.25); fn_tostr_num(1.25)
fn_tostr_num(1.25); fn_tostr_num(1.25); fn_tostr_num(1.25); fn_tostr_num(1.25)

jit.flush()
fn_tostr_char(65); fn_tostr_char(65); fn_tostr_char(65); fn_tostr_char(65)
fn_tostr_char(65); fn_tostr_char(65); fn_tostr_char(65); fn_tostr_char(65)
fn_tostr_char(65); fn_tostr_char(65); fn_tostr_char(65); fn_tostr_char(65)

jit.flush()
fn_strto("0.5"); fn_strto("0.5"); fn_strto("0.5"); fn_strto("0.5")
fn_strto("0.5"); fn_strto("0.5"); fn_strto("0.5"); fn_strto("0.5")
fn_strto("0.5"); fn_strto("0.5"); fn_strto("0.5"); fn_strto("0.5")

jit.flush()
fn_conv_num_int(7); fn_conv_num_int(7); fn_conv_num_int(7); fn_conv_num_int(7)
fn_conv_num_int(7); fn_conv_num_int(7); fn_conv_num_int(7); fn_conv_num_int(7)
fn_conv_num_int(7); fn_conv_num_int(7); fn_conv_num_int(7); fn_conv_num_int(7)

jit.flush()
fn_conv_int_num(2.5); fn_conv_int_num(2.5); fn_conv_int_num(2.5)
fn_conv_int_num(2.5)
fn_conv_int_num(2.5); fn_conv_int_num(2.5); fn_conv_int_num(2.5)
fn_conv_int_num(2.5)
fn_conv_int_num(2.5); fn_conv_int_num(2.5); fn_conv_int_num(2.5)
fn_conv_int_num(2.5)

jit.flush()
fn_conv_i64_num(3); fn_conv_i64_num(3); fn_conv_i64_num(3); fn_conv_i64_num(3)
fn_conv_i64_num(3); fn_conv_i64_num(3); fn_conv_i64_num(3); fn_conv_i64_num(3)
fn_conv_i64_num(3); fn_conv_i64_num(3); fn_conv_i64_num(3); fn_conv_i64_num(3)

jit.flush()
fn_conv_num_i64(3.5); fn_conv_num_i64(3.5); fn_conv_num_i64(3.5)
fn_conv_num_i64(3.5)
fn_conv_num_i64(3.5); fn_conv_num_i64(3.5); fn_conv_num_i64(3.5)
fn_conv_num_i64(3.5)
fn_conv_num_i64(3.5); fn_conv_num_i64(3.5); fn_conv_num_i64(3.5)
fn_conv_num_i64(3.5)

jit.flush()
fn_conv_u64_num(3.5); fn_conv_u64_num(3.5); fn_conv_u64_num(3.5)
fn_conv_u64_num(3.5)
fn_conv_u64_num(3.5); fn_conv_u64_num(3.5); fn_conv_u64_num(3.5)
fn_conv_u64_num(3.5)
fn_conv_u64_num(3.5); fn_conv_u64_num(3.5); fn_conv_u64_num(3.5)
fn_conv_u64_num(3.5)

jit.flush()
fn_conv_i64_int(3); fn_conv_i64_int(3); fn_conv_i64_int(3); fn_conv_i64_int(3)
fn_conv_i64_int(3); fn_conv_i64_int(3); fn_conv_i64_int(3); fn_conv_i64_int(3)
fn_conv_i64_int(3); fn_conv_i64_int(3); fn_conv_i64_int(3); fn_conv_i64_int(3)

jit.flush()
fn_conv_int_i64(5LL); fn_conv_int_i64(5LL); fn_conv_int_i64(5LL)
fn_conv_int_i64(5LL)
fn_conv_int_i64(5LL); fn_conv_int_i64(5LL); fn_conv_int_i64(5LL)
fn_conv_int_i64(5LL)
fn_conv_int_i64(5LL); fn_conv_int_i64(5LL); fn_conv_int_i64(5LL)
fn_conv_int_i64(5LL)

jit.flush()
fn_conv_u64_int(3); fn_conv_u64_int(3); fn_conv_u64_int(3); fn_conv_u64_int(3)
fn_conv_u64_int(3); fn_conv_u64_int(3); fn_conv_u64_int(3); fn_conv_u64_int(3)
fn_conv_u64_int(3); fn_conv_u64_int(3); fn_conv_u64_int(3); fn_conv_u64_int(3)

jit.flush()
fn_conv_u32(3.5); fn_conv_u32(3.5); fn_conv_u32(3.5); fn_conv_u32(3.5)
fn_conv_u32(3.5); fn_conv_u32(3.5); fn_conv_u32(3.5); fn_conv_u32(3.5)
fn_conv_u32(3.5); fn_conv_u32(3.5); fn_conv_u32(3.5); fn_conv_u32(3.5)

jit.flush()
fn_conv_flt(3.5); fn_conv_flt(3.5); fn_conv_flt(3.5); fn_conv_flt(3.5)
fn_conv_flt(3.5); fn_conv_flt(3.5); fn_conv_flt(3.5); fn_conv_flt(3.5)
fn_conv_flt(3.5); fn_conv_flt(3.5); fn_conv_flt(3.5); fn_conv_flt(3.5)

jit.flush()
fn_u32_cmp(3, 3); fn_u32_cmp(3, 3); fn_u32_cmp(3, 3); fn_u32_cmp(3, 3)
fn_u32_cmp(3, 3); fn_u32_cmp(3, 3); fn_u32_cmp(3, 3); fn_u32_cmp(3, 3)
fn_u32_cmp(3, 5); fn_u32_cmp(3, 5); fn_u32_cmp(3, 5); fn_u32_cmp(3, 5)
fn_u32_cmp(3, 5); fn_u32_cmp(3, 5); fn_u32_cmp(3, 5); fn_u32_cmp(3, 5)
fn_u32_cmp(5, 3); fn_u32_cmp(5, 3); fn_u32_cmp(5, 3); fn_u32_cmp(5, 3)
fn_u32_cmp(5, 3); fn_u32_cmp(5, 3); fn_u32_cmp(5, 3); fn_u32_cmp(5, 3)
