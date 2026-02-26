local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

impls.IRNodeFREFP32 = {}
ir_node.extended(impls.IRNodeFREFP32, ir_node.ir_node_base)

function impls.IRNodeFREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    if right_op == 'tab.meta' then
        local table_info = ctx.tab_info[tonumber(left_op)]
        local result = nil
        if table_info.meta == nil then
            table_info.meta, result = ctx.mem_stack:allocate_child(
                self:get_ssa_reference(), table_info.mem_ref, "__metatable"
            )
        end
        ctx.tab_info[self:get_ssa_reference()] = {
            mem_ref = table_info.meta,
            meta = "NO META for P32!",
        }
        if result then
            return result
        else
            return '; ' .. table_info.mem_ref .. ' to ' .. table_info.meta
        end
    else
        utils.unreachable(false, right_op)
    end
end

function impls.IRNodeFREFP32.is_implemented(_flags, _type, _opcode,
                                              _left_op, right_op)
    if right_op == 'tab.meta' then
        return true
    end
    return false
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
