local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

-- Raw FFI loads read `nbytes` little-endian bytes from the flat
-- byte-addressed xmem and `finalize` them into the value the
-- op-stack expects for `typ` (a BitVec 64 for int/i64, a double
-- for num). See arith_utils.xmem_load.
local function make_xload(typ, nbytes, finalize)
    local cls = {}
    ir_node.extended(cls, ir_node.ir_node_base)
    function cls:to_smt_lib(ctx)
        local ptr = ir_node.retrieve_i64_op(
            self:get_left_op(), ctx, 'p64'
        )
        local raw = arith_utils.xmem_load(ctx.xmem_cur, ptr, nbytes)
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
