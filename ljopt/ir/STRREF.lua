-- A pointer into a string's bytes: `STRREF s, off`, which SNEW
-- then turns back into a string. It is what string.sub and
-- friends lower to.
--
-- The SMT String theory has no address of a byte, so the pointer
-- is carried as the pair it stands for -- the string and the
-- offset into it. p32-val already holds an Int beside a MemCell,
-- so the offset goes in the Int and the string in the cell.
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeSTRREFP32 = {}
ir_node.extended(impls.IRNodeSTRREFP32, ir_node.ir_node_base)

function impls.IRNodeSTRREFP32:to_smt_lib(ctx)
    local ssa_ref = self:get_ssa_reference()
    local base = ir_node.retrieve_str_op(self:get_left_op(), ctx)
    local off = ir_node.retrieve_int_op(self:get_right_op(), ctx, op_type.INT)
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.ANY,
            ('(p32-val (bv2nat %s) (str-val %s))'):format(off, base))
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
