local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

local IRNodeXSTOREBase = {}
ir_node.extended(IRNodeXSTOREBase, ir_node.ir_node_base)

-- Reduce the store's right operand to a bitvector: int/i64/u32
-- are already bitvectors on the op-stack, a num and a float are
-- reinterpreted to their IEEE-754 bits via `fp_to_bits`.
local function store_value_bv(right, ctx, typ)
    if typ == op_type.NUM then
        local fp = right:is_ssa()
            and ctx.op_stack:load(right:get_ssa(), typ)
            or ir_node.retrieve_num_op(right, ctx, typ)
        return arith_utils.fp_to_bits(fp, 64)
    elseif typ == 'flt' then
        assert(right:is_ssa(), 'flt XSTORE expects an SSA operand')
        return arith_utils.fp_to_bits(
            ctx.op_stack:load(right:get_ssa(), typ), 32
        )
    elseif right:is_ssa() then
        return ctx.op_stack:load(right:get_ssa(), typ)
    elseif typ == op_type.I64 and right:is_i64() then
        return ('#x%016x'):format(tonumber(right:get_i64()))
    end
    return ir_node.retrieve_int_op(right, ctx, typ)
end

-- Raw FFI stores decompose the value into `self.nbytes`
-- little-endian bytes written to the flat byte-addressed xmem,
-- bumping the xmem version so later loads observe the store.
function IRNodeXSTOREBase:to_smt_lib(ctx)
    local ptr = ir_node.retrieve_i64_op(self:get_left_op(), ctx, 'p64')
    local bv, tie = store_value_bv(self:get_right_op(), ctx, self.typ)

    local prev = ctx.xmem_cur
    local new_ver = ctx.xmem_versions + 1
    ctx.xmem_versions = new_ver
    local new_name = ('xmem_%s_v%d'):format(ctx.xmem_suffix, new_ver)
    ctx.xmem_cur = new_name

    local decl = (
        '(declare-fun %s () (Array (_ BitVec 64) (_ BitVec 8)))'
    ):format(new_name)
    local store_eq = ('(assert (= %s %s))'):format(
        new_name, arith_utils.xmem_store(prev, ptr, bv, self.nbytes)
    )
    if tie then
        return ('%s\n%s\n%s'):format(tie, decl, store_eq)
    end
    return ('%s\n%s'):format(decl, store_eq)
end

impls.IRNodeXSTOREInt = { typ = op_type.INT, nbytes = 4 }
ir_node.extended(impls.IRNodeXSTOREInt, IRNodeXSTOREBase)

impls.IRNodeXSTOREI64 = { typ = op_type.I64, nbytes = 8 }
ir_node.extended(impls.IRNodeXSTOREI64, IRNodeXSTOREBase)

impls.IRNodeXSTORENum = { typ = op_type.NUM, nbytes = 8 }
ir_node.extended(impls.IRNodeXSTORENum, IRNodeXSTOREBase)

impls.IRNodeXSTOREFlt = { typ = 'flt', nbytes = 4 }
ir_node.extended(impls.IRNodeXSTOREFlt, IRNodeXSTOREBase)

-- u32: 4-byte store; the value is a zero-extended 64-bit BV on
-- the op-stack, xmem_store writes its low 4 bytes (same as int).
impls.IRNodeXSTOREU32 = { typ = 'u32', nbytes = 4 }
ir_node.extended(impls.IRNodeXSTOREU32, IRNodeXSTOREBase)

impls.IRNodeXSTOREU64 = { typ = 'u64', nbytes = 8 }
ir_node.extended(impls.IRNodeXSTOREU64, IRNodeXSTOREBase)

-- Narrow C integer stores. The value handed to them is int-typed
-- (LuaJIT keeps narrow arithmetic at int width and truncates only
-- at the store), and xmem_store already writes just the low
-- `nbytes` bytes -- so the truncation is exactly the byte count.
impls.IRNodeXSTOREI8 = { typ = 'i8', nbytes = 1 }
ir_node.extended(impls.IRNodeXSTOREI8, IRNodeXSTOREBase)

impls.IRNodeXSTOREU8 = { typ = 'u8', nbytes = 1 }
ir_node.extended(impls.IRNodeXSTOREU8, IRNodeXSTOREBase)

impls.IRNodeXSTOREI16 = { typ = 'i16', nbytes = 2 }
ir_node.extended(impls.IRNodeXSTOREI16, IRNodeXSTOREBase)

impls.IRNodeXSTOREU16 = { typ = 'u16', nbytes = 2 }
ir_node.extended(impls.IRNodeXSTOREU16, IRNodeXSTOREBase)

-- float32: 4 bytes of IEEE single, see store_value_bv.
impls.IRNodeXSTOREFlt = { typ = 'flt', nbytes = 4 }
ir_node.extended(impls.IRNodeXSTOREFlt, IRNodeXSTOREBase)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance,
}
