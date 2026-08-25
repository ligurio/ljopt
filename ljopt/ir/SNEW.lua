-- Builds a string from a STRREF pointer and a length. XSNEW is
-- the same thing for a buffer-allocated string.
--
-- The pointer already carries the string it points into and the
-- offset, so the new string is that slice -- `str.substr` takes
-- exactly a base, a start and a length.
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

local IRNodeSNEWStr = {}
ir_node.extended(IRNodeSNEWStr, ir_node.ir_node_base)

function IRNodeSNEWStr:to_smt_lib(ctx)
    local ssa_ref = self:get_ssa_reference()
    local ptr = ir_node.retrieve_raw_val(self:get_left_op(), ctx)
    local len = ir_node.retrieve_int_op(self:get_right_op(), ctx, op_type.INT)
    local data = ('(str.substr (get-str (get-p32-idx %s)) (get-p32-tab %s) %s)')
        :format(ptr, ptr, ('(bv2nat %s)'):format(len))
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.STR, data)
    )
end

impls.IRNodeSNEWStr = IRNodeSNEWStr
impls.IRNodeXSNEWStr = IRNodeSNEWStr

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
