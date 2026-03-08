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

local function const_num_to_memcell(num_value)
    return ("(int-val %s)"):format(const_num_to_smt_bv(num_value))
end

local function memcell_to_str(memcell)
    return ("(get-str %s)"):format(memcell)
end
local function const_str_to_memcell(num_value)
    return ('(str-val "%s")'):format(num_value)
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

return {
    i32_overflow_check = i32_overflow_check,
    const_num_to_smt_bv = const_num_to_smt_bv,
    const_num_to_memcell = const_num_to_memcell,
    const_str_to_memcell = const_str_to_memcell,
    const_i64_to_memcell = const_i64_to_memcell,
    memcell_to_str = memcell_to_str,
    const_int_to_smt_bv = const_int_to_smt_bv,
    const_i64_to_smt_bv = const_i64_to_smt_bv,
    smt_int_to_fp = smt_int_to_fp,
    smt_i64_to_fp = smt_i64_to_fp,
}
