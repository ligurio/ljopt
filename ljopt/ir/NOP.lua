local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeNOP = {}
ir_node.extended(IRNodeNOP, ir_node.ir_node_base)

function IRNodeNOP:to_smt_lib(ctx)
    local ssa_ref = self:get_ssa_reference()
    if self:get_flags().irt_guard then
        -- Old versions of Lua sometimes have
        -- NOP flag set to `true`.
        return ctx.te_stack:store(ssa_ref, 'true') .. '\n'
    else
        return ''
    end
end

local function instance(_node_str)
    return IRNodeNOP
end

return {
    instance = instance
}
