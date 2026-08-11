local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')

-- CONV modes narrowing to a C integer type, and the width each
-- one truncates to. Only these four exist: LuaJIT promotes every
-- narrower-than-int C type to `int` for arithmetic, so a
-- narrowing cast is the only place the width is visible.
local NARROW_CONV = {
    ['int.i8']  = 8,
    ['int.u8']  = 8,
    ['int.i16'] = 16,
    ['int.u16'] = 16,
}

-- Guarded conversions out of `num`, and the signed width the
-- value has to fit for the guard to hold. Only these two are ever
-- emitted as a trace exit (IRCONV_CHECK / IRCONV_INDEX, from
-- lj_opt_narrow.c and the recorder's index/toint paths); the
-- unsigned and FFI casts are IRCONV_ANY, which is not a guard.
local NUM_SRC_GUARD = {
    ['int.num'] = 32,
    ['i64.num'] = 64,
}

local IRNodeCONV = {}
ir_node.extended(IRNodeCONV, ir_node.ir_node_base)

function IRNodeCONV:to_smt_lib(ctx)
    local left_op
    local right_op = self:get_right_op():get_lit()
    local data = ''

    local parsed_right_op = {}
    for i in string.gmatch(right_op, '%S+') do
        table.insert(parsed_right_op, i)
    end

    -- TODO: Support other conversions.
    if parsed_right_op[1] == 'num.int' then
        left_op = self:get_left_op()
        data = ir_node.retrieve_int_op(left_op, ctx, 'int')
        -- Convert int to floating point `num`.
        data = arith_utils.smt_int_to_fp(data)
    elseif parsed_right_op[1] == 'int.num' then
        left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
        -- TODO handle inputs that are out of range.
        -- LuaJIT follows C semantic when converting
        -- num -> int.
        -- And in C it's RTZ as stated in standard 6.3.1.4:
        -- luacheck: push no max_comment_line_length
        -- https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1256.pdf
        -- luacheck: pop
        -- Convert at 32-bit width: the result is an int32
        -- (cvttsd2si r32), so out-of-range doubles wrap into the
        -- canonical form instead of escaping into the high bits.
        data = arith_utils.wrap_i32(
            string.format('((_ fp.to_sbv 64) RTZ %s)', left_op)
        )
    elseif parsed_right_op[1] == 'num.i64' then
        left_op = self:get_left_op()
        data = ir_node.retrieve_i64_op(left_op, ctx, 'int')
        -- Convert int to floating point `num`.
        data = arith_utils.smt_i64_to_fp(data)
    elseif parsed_right_op[1] == 'int.i64' then
        left_op = ir_node.retrieve_i64_op(self:get_left_op(), ctx, 'i64')
        -- Truncate to lower 32 bits, then sign-extend back to 64.
        data = ('((_ sign_extend 32) ((_ extract 31 0) %s))'):format(left_op)
    -- u64.int is the same widening as i64.int; the `sext` suffix,
    -- not the destination type, decides sign- vs zero-extension.
    elseif parsed_right_op[1] == 'i64.int' or
           parsed_right_op[1] == 'u64.int' then
        local lo = ir_node.retrieve_int_op(self:get_left_op(), ctx, 'int')
        if parsed_right_op[2] == 'sext' then
            data = ('((_ sign_extend 32) ((_ extract 31 0) %s))'):format(lo)
        else
            data = ('((_ zero_extend 32) ((_ extract 31 0) %s))'):format(lo)
        end
    elseif parsed_right_op[1] == 'i64.num' then
        left_op = ir_node.retrieve_num_op(
            self:get_left_op(), ctx, 'num'
        )
        -- TODO handle inputs that are out of range.
        data = string.format('((_ fp.to_sbv 64) RNE %s)', left_op)
    -- Unsigned 32-bit conversions. u32 values are stored as
    -- zero-extended 64-bit BVs (canonical form); see ir/BinOp.
    elseif parsed_right_op[1] == 'u32.int' then
        left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, 'int')
        data = arith_utils.wrap_u32(left_op)
    elseif parsed_right_op[1] == 'u32.i64' or
           parsed_right_op[1] == 'u32.u64' then
        -- 64-bit -> u32: truncate to low 32 bits, zero-extend.
        left_op = ir_node.retrieve_i64_op(self:get_left_op(), ctx, 'i64')
        data = arith_utils.wrap_u32(left_op)
    -- Unsigned 32-bit conversions. u32 values are stored as
    -- zero-extended 64-bit BVs (canonical form); see ir/BinOp.
    elseif parsed_right_op[1] == 'int.u32' then
        left_op = ir_node.retrieve_u32_op(self:get_left_op(), ctx, 'u32')
        data = ('((_sign_extend 32) ((_ extract 31 0) %s))'):format(left_op)
    elseif parsed_right_op[1] == 'i64.u32' or
           parsed_right_op[1] == 'u64.u32' then
        -- u32 -> 64-bit: zero-extend (unsigned widening).
        left_op = ir_node.retrieve_u32_op(self:get_left_op(), ctx, 'u32')
        data = arith_utils.wrap_u32(left_op)
    -- float32 <-> double, the FFI `float` conversions. Narrowing
    -- rounds (RNE, what C does); widening back is exact.
    elseif parsed_right_op[1] == 'flt.num' then
        left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
        data = ('((_ to_fp 8 24) RNE %s)'):format(left_op)
    elseif parsed_right_op[1] == 'num.flt' then
        left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'flt')
        data = ('((_ to_fp 11 53) RNE %s)'):format(left_op)
    elseif parsed_right_op[1] == 'num.u32' then
        -- u32 -> num: unsigned integer to floating point.
        left_op = ir_node.retrieve_u32_op(self:get_left_op(), ctx, 'u32')
        data = arith_utils.smt_u32_to_fp(left_op)
    elseif parsed_right_op[1] == 'u32.num' then
        -- num -> u32: C truncation toward zero (RTZ), unsigned.
        left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
        data = ('((_ zero_extend 32) ((_ fp.to_ubv 32) RTZ %s))'):format(
            left_op
        )
    -- Narrowing casts to a C integer type (`ffi.cast("int8_t", x)`
    -- and friends). The IR result stays `int` -- LuaJIT has no
    -- arithmetic at these widths -- so the conversion is a
    -- truncate to the C width followed by the re-extension that
    -- puts the value back in canonical 64-bit op-stack form:
    -- sign for the signed types, zero for the unsigned ones.
    -- The `sext` suffix in the mode literal marks which, and only
    -- ever appears on i8/i16.
    elseif NARROW_CONV[parsed_right_op[1]] ~= nil then
        local nbits = NARROW_CONV[parsed_right_op[1]]
        left_op = ir_node.retrieve_int_op(self:get_left_op(), ctx, 'int')
        local extend = parsed_right_op[2] == 'sext'
            and 'sign_extend' or 'zero_extend'
        data = ('((_ %s %d) ((_ extract %d 0) %s))'):format(
            extend, 64 - nbits, nbits - 1, left_op
        )
    elseif parsed_right_op[1] == 'int.u64' then
        -- 64-bit -> int: keep the low 32 bits, sign-extend back.
        left_op = ir_node.retrieve_i64_op(self:get_left_op(), ctx, 'u64')
        data = ('((_ sign_extend 32) ((_ extract 31 0) %s))'):format(left_op)
    elseif parsed_right_op[1] == 'num.u64' then
        -- u64 -> num: *unsigned* widening, so fp.to_fp_unsigned.
        -- Using the signed form would turn every value above
        -- 2^63 into a negative double.
        left_op = ir_node.retrieve_i64_op(self:get_left_op(), ctx, 'u64')
        data = ('((_ to_fp_unsigned 11 53) RNE %s)'):format(left_op)
    elseif parsed_right_op[1] == 'u64.num' then
        -- num -> u64: C truncation toward zero, unsigned.
        left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
        data = ('((_ fp.to_ubv 64) RTZ %s)'):format(left_op)
    elseif parsed_right_op[1] == 'flt.num' then
        -- num -> flt: round a double (fp 11 53) to float32 (fp 8 24).
        -- Rounding is RNE, matching hardware cvtsd2ss.
        left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
        data = ('((_ to_fp 8 24) RNE %s)'):format(left_op)
    elseif parsed_right_op[1] == 'num.flt' then
        -- flt -> num: widen float32 back to a double (exact).
        left_op = ctx.op_stack:load(self:get_left_op():get_ssa(), 'flt')
        data = ('((_ to_fp 11 53) RNE %s)'):format(left_op)
    else
        assert(false, 'Unsupported type conversion: '..right_op)
    end

    local ssa_ref = self:get_ssa_reference()
    local te = ""
    if self:get_flags().irt_guard then
        -- A guarded num -> integer CONV (IRCONV_CHECK /
        -- IRCONV_INDEX, dumped as `check` / `index`) exits the
        -- trace unless the double is an exact integer of the
        -- destination width, so its exit condition is that test
        -- -- not `true`. Modelling it as `true` made every such
        -- CONV disagree with the ADDOV that lj_opt_narrow emits
        -- in its place, whose exit condition IS modelled: the two
        -- exit bitvectors differed on any overflowing input and
        -- the narrowing read as a miscompile. Every other guarded
        -- CONV keeps the assumed-true exit.
        local guard = 'true'
        local dst_bits = NUM_SRC_GUARD[parsed_right_op[1]]
        if dst_bits then
            guard = arith_utils.num_to_int_guard(
                left_op, dst_bits)
        end
        te = ctx.te_stack:store(ssa_ref, guard) .. '\n'
    end

    -- Propagate constant value through conversion.
    local raw_left = self:get_left_op()
    local const_val
    if raw_left:is_num() then
        const_val = raw_left:get_num()
    elseif raw_left:is_ssa() then
        const_val = ctx.const_nums[raw_left:get_ssa()]
    end
    if const_val ~= nil then
        ctx.const_nums[ssa_ref] = const_val
    end

    return te .. ctx.op_stack:store(
        ssa_ref, self:get_type(), data
    )
end

local function instance(_node_str)
    return IRNodeCONV
end

return {
    instance = instance
}
