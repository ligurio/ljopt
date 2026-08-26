local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

-- Raw FFI loads read `nbytes` little-endian bytes from the flat
-- byte-addressed xmem and `finalize` them into the value the
-- op-stack expects for `typ` (a BitVec 64 for int/i64, a double
-- for num). See arith_utils.xmem_load.
-- A STRREF is not an xmem address. STRREF.lua carries it as the
-- (string, offset) pair the SMT String theory forces, in a
-- p32-val cell, so an xmem load through it would decode that cell
-- with the wrong ADT accessor and hand the solver a free value.
-- Read the string's bytes instead, little-endian, the way the
-- unaligned compares merge_eqne_snew_kgc emits do.
--
-- str.at past the end gives "" and str.to_code gives -1 for it,
-- which int2bv wraps to 0xff. That only shows up on a read the
-- recorder guards against anyway: merge_eqne_snew_kgc compares
-- the length first.
local function str_bytes(cell, nbytes)
    local off = ('(get-p32-tab %s)'):format(cell)
    local base = ('(get-str (get-p32-idx %s))'):format(cell)
    local byte = '((_ int2bv 8) (str.to_code (str.at %s (+ %s %d))))'
    if nbytes == 1 then
        return byte:format(base, off, 0)
    end
    local parts = {}
    for i = nbytes - 1, 0, -1 do
        parts[#parts + 1] = byte:format(base, off, i)
    end
    return ('(concat %s)'):format(table.concat(parts, ' '))
end

local function make_xload(typ, nbytes, finalize)
    local cls = {}
    ir_node.extended(cls, ir_node.ir_node_base)
    function cls:to_smt_lib(ctx)
        local left = self:get_left_op()
        local raw
        if left:is_ssa() and ctx.strref_ptrs[left:get_ssa()] then
            raw = str_bytes(
                ctx.op_stack:load(left:get_ssa(), op_type.ANY), nbytes
            )
        else
            local ptr = ir_node.retrieve_i64_op(left, ctx, 'p64')
            raw = arith_utils.xmem_load(ctx.xmem_cur, ptr, nbytes)
        end
        return ctx.op_stack:store(self:get_ssa_reference(), typ, finalize(raw))
    end
    return cls
end

-- Sign- or zero-extend an `nbits`-wide raw load into the 64-bit
-- op-stack cell, matching the movsx/movzx the backend emits.
local function sext(nbits)
    return function(raw)
        return ('((_ sign_extend %d) %s)'):format(64 - nbits, raw)
    end
end

local function zext(nbits)
    return function(raw)
        return ('((_ zero_extend %d) %s)'):format(64 - nbits, raw)
    end
end

-- int is a 32-bit signed load sign-extended into the 64-bit cell.
impls.IRNodeXLOADInt = make_xload(op_type.INT, 4, sext(32))
impls.IRNodeXLOADI64 = make_xload(op_type.I64, 8, function(raw)
    return raw
end)
-- A pointer read out of raw memory, e.g. an FFI function pointer
-- picked out of an array of them. The same 8-byte load as i64;
-- the type only says how the value is used afterwards.
impls.IRNodeXLOADP64 = make_xload('p64', 8, function(raw)
    return raw
end)
-- u32 is a 32-bit unsigned load zero-extended into the 64-bit
-- cell.
impls.IRNodeXLOADU32 = make_xload('u32', 4, zext(32))
impls.IRNodeXLOADNum = make_xload(op_type.NUM, 8, function(raw)
    return ('((_ to_fp 11 53) %s)'):format(raw)
end)

-- Narrow C integer loads. LuaJIT never does arithmetic at these
-- widths -- the recorder emits `i8 XLOAD` feeding an `int ADD`
-- directly -- so the extension to the full 64-bit cell has to
-- happen here, signed for i8/i16 and unsigned for u8/u16.
impls.IRNodeXLOADI8 = make_xload('i8', 1, sext(8))
impls.IRNodeXLOADU8 = make_xload('u8', 1, zext(8))
impls.IRNodeXLOADI16 = make_xload('i16', 2, sext(16))
impls.IRNodeXLOADU16 = make_xload('u16', 2, zext(16))

-- u64 fills the cell exactly; signedness only shows up in the
-- ops applied to it (bvudiv/bvurem, unsigned compares).
impls.IRNodeXLOADU64 = make_xload('u64', 8, function(raw)
    return raw
end)

-- float32. The op-stack keeps `flt` as an (_ FloatingPoint 8 24)
-- (see the flt entries in smt_context's type2bv/bv2type), so the
-- 4 raw bytes are reinterpreted, not converted -- no rounding is
-- involved in a load.
impls.IRNodeXLOADFlt = make_xload('flt', 4, function(raw)
    return ('((_ to_fp 8 24) %s)'):format(raw)
end)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance,
}
