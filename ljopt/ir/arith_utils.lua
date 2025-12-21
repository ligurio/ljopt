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

return {
    i32_overflow_check = i32_overflow_check,
}
