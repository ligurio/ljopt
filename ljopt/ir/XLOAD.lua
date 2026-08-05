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

-- int is a 32-bit signed load sign-extended into the 64-bit cell.
impls.IRNodeXLOADInt = make_xload(op_type.INT, 4, function(raw)
    return ('((_ sign_extend 32) %s)'):format(raw)
end)
impls.IRNodeXLOADI64 = make_xload(op_type.I64, 8, function(raw)
    return raw
end)
-- u32 is a 32-bit unsigned load zero-extended into the 64-bit
-- cell.
impls.IRNodeXLOADU32 = make_xload('u32', 4, function(raw)
    return ('((_ zero_extend 32) %s)'):format(raw)
end)
impls.IRNodeXLOADNum = make_xload(op_type.NUM, 8, function(raw)
    return ('((_ to_fp 11 53) %s)'):format(raw)
end)

impls.IRNodeXLOADFlt = make_xload('flt', 4, function(raw)
    return ('((_ to_fp 8 24) %s)'):format(raw)
end)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance,
}
