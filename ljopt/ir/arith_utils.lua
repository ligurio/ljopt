local ffi = require("ffi")
local bit = require("bit")

local MAX_INT32 = 2^31

-- x >= INT_MIN && x <= INT_MAX
local function i32_overflow_check(value)
    -- We have only one op-stack to store results
    -- of IR operations. It's values are 64-bit vectors.
    -- Simplest solution is to use 64-bit operations,
    -- otherwise we should cast back and forth.
    local positive_overflow =
        string.format('(bvsle %s #x%016X)', value, MAX_INT32 - 1)
    local negative_overflow =
        string.format('(bvsge %s (bvneg #x%016X))', value, MAX_INT32)
    local overflow_check = string.format('(and %s %s)',
        positive_overflow, negative_overflow)
    return overflow_check
end

local function const_num_to_smt_bv(num_value)
    local u = ffi.new("union { double d; uint64_t i; }")
    u.d = num_value
    return string.format("#x%s", bit.tohex(u.i, 16))
end

local function const_num_to_smt_fp(num_value)
    return string.format("((_ to_fp 11 53) %s)", const_num_to_smt_bv(num_value))
end

local function const_num_to_memcell(num_value)
    return ("(fp-val %s)"):format(const_num_to_smt_fp(num_value))
end

local function memcell_to_str(memcell)
    return ("(get-str %s)"):format(memcell)
end
local function const_str_to_memcell(num_value)
    return ('(str-val "%s")'):format(num_value)
end

local function const_str_to_smt_str(str)
    return ('"%s"'):format(str)
end

local function const_int_to_smt_bv(int_value)
    return string.format("#x%016X", int_value)
end

local function const_i64_to_smt_bv(int_value)
    local u = ffi.new("union { int64_t i; uint64_t u; }")
    u.i = int_value

    -- Convert uint64_t cdata to hex string without
    -- using string.format on cdata.
    local lo = tonumber(ffi.cast("uint32_t", bit.band(u.u, 0xFFFFFFFF)))
    local hi = tonumber(ffi.cast("uint32_t", bit.rshift(u.u, 32)))

    return string.format("#x%08X%08X", hi, lo)
end

local function const_i64_to_memcell(i64_value)
    return ("(int-val %s)"):format(const_i64_to_smt_bv(i64_value))
end

local function smt_int_to_fp(int_value)
    -- Extract lower 32-bit and extend with sign.
    local bv = ("RTZ ((_ sign_extend 32) ((_ extract 31 0) %s))"):format(
        int_value
    )
    -- Convert 64-bitvector to floating point `num`.
    return string.format("((_ to_fp 11 53) %s)", bv)
end

local function smt_i64_to_fp(i64_value)
    return string.format("((_ to_fp 11 53) RTZ %s)", i64_value)
end

-- Canonicalize a 64-bit BV holding a u32 result: keep the low 32
-- bits and zero-extend. This both wraps unsigned 32-bit
-- arithmetic at 2^32 (correct overflow) and keeps the value in
-- canonical form (high 32 bits = 0), so it stays a non-negative
-- 64-bit integer and unsigned compares / FP conversions behave
-- correctly.
local function wrap_u32(bv_value)
    return ('((_ zero_extend 32) ((_ extract 31 0) %s))'):format(bv_value)
end

-- Convert a u32 value (stored as a zero-extended 64-bit BV) to a
-- floating-point `num`. The canonical u32 is always non-negative,
-- so the signed bitvector-to-FP conversion gives the unsigned
-- value.
local function smt_u32_to_fp(u32_value)
    return string.format(
        "((_ to_fp 11 53) RNE %s)", wrap_u32(u32_value)
    )
end

-- Convert FP `num` to int. Currently returns bv64 (32-bit signed
-- value sign-extended to 64 bits); will become real Int when
-- op-stack widens.
local function smt_fp_to_int(fp_value, rounding)
    return ('((_ sign_extend 32) ((_ fp.to_sbv 32) %s %s))'):format(
        rounding or 'RTZ', fp_value
    )
end

-- Raw FFI memory is modelled byte-granular as a flat array
-- `xmem : (Array (_ BitVec 64) (_ BitVec 8))`, so overlapping,
-- sub-word and type-punned accesses alias correctly (SMT array
-- theory reasons about pointer equality per byte). x86-64 is
-- little-endian: byte i of a value lives at address ptr + i.

-- Address `ptr` (a BitVec 64) offset by `i` bytes.
local function xmem_addr(ptr, i)
    if i == 0 then
        return ptr
    end
    return ('(bvadd %s #x%016x)'):format(ptr, i)
end

-- Nested `store` writing the low `nbytes` bytes of `bv`
-- (width >= 8*nbytes) into `base` from `ptr`, little-endian.
local function xmem_store(base, ptr, bv, nbytes)
    local expr = base
    for i = 0, nbytes - 1 do
        local byte = ('((_ extract %d %d) %s)'):format(8 * i + 7, 8 * i, bv)
        expr = ('(store %s %s %s)'):format(expr, xmem_addr(ptr, i), byte)
    end
    return expr
end

-- Read `nbytes` little-endian bytes from `mem` at `ptr` and
-- concatenate them into a BitVec of width 8*nbytes (the byte at
-- the highest address is the most significant).
local function xmem_load(mem, ptr, nbytes)
    local function sel(i)
        return ('(select %s %s)'):format(mem, xmem_addr(ptr, i))
    end
    local expr = sel(nbytes - 1)
    for i = nbytes - 2, 0, -1 do
        expr = ('(concat %s %s)'):format(expr, sel(i))
    end
    return expr
end

local fp_bits_kind = {
    [64] = {fn = 'fp2bv64', sort = '(_ to_fp 11 53)'},
}

-- The IEEE bits of the float `fp`, as a BitVec of `width`.
--
-- Returns two strings: the bits, and the assertion that defines
-- them. The bits are an uninterpreted function (see
-- smt_constants), so the assertion is not optional -- without it
-- the result is an arbitrary bitvector. Callers must emit it
-- before the term that uses the bits.
local function fp_to_bits(fp, width)
    local kind = assert(fp_bits_kind[width], 'No fp bits for ' .. width)
    return ('(%s %s)'):format(kind.fn, fp),
        ('(assert (= %s (%s (%s %s))))'):format(fp, kind.sort, kind.fn, fp)
end

-- LuaJIT treats -0.0 and +0.0 as the same table key.
-- Accepts a MemCell and returns a MemCell: for int-val keys,
-- normalizes -0.0 to +0.0; str-val keys pass through unchanged.
local function normalize_table_key(memcell)
    return ('(ite ((_ is fp-val) %s)' ..
            ' (ite (fp.isZero (get-fp %s))' ..
            ' (fp-val ((_ to_fp 11 53) #x0000000000000000)) %s) %s)'):format(
               memcell, memcell, memcell, memcell
            )
end

return {
    i32_overflow_check = i32_overflow_check,
    const_num_to_smt_bv = const_num_to_smt_bv,
    const_num_to_smt_fp = const_num_to_smt_fp,
    const_num_to_memcell = const_num_to_memcell,
    const_str_to_memcell = const_str_to_memcell,
    const_str_to_smt_str = const_str_to_smt_str,
    const_i64_to_memcell = const_i64_to_memcell,
    const_int_to_smt_bv = const_int_to_smt_bv,
    const_i64_to_smt_bv = const_i64_to_smt_bv,
    fp_to_bits = fp_to_bits,
    memcell_to_str = memcell_to_str,
    normalize_table_key = normalize_table_key,
    xmem_store = xmem_store,
    xmem_load = xmem_load,
    smt_fp_to_int = smt_fp_to_int,
    smt_int_to_fp = smt_int_to_fp,
    smt_i64_to_fp = smt_i64_to_fp,
    smt_u32_to_fp = smt_u32_to_fp,
    wrap_u32 = wrap_u32,
}
