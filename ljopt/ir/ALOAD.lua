local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeALOADNum = {}
ir_node.extended(impls.IRNodeALOADNum, ir_node.ir_node_base)

function impls.IRNodeALOADNum:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local tab_left, idx_left = ir_node.retrieve_tab_ref(left_op, ctx)

    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.NUM,
            ctx.mem_stack:load_index(tab_left, idx_left, op_type.NUM)
        )
    )
end

impls.IRNodeALOADTab = {}
ir_node.extended(impls.IRNodeALOADTab, ir_node.ir_node_base)

function impls.IRNodeALOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local _, _, raw_cell = ir_node.retrieve_tab_ref(left_op, ctx)

    local ssa_ref = self:get_ssa_reference()
    -- An array slot that holds no table is a state the trace
    -- can be in -- a fresh table's slots are all nil -- so decode
    -- it with get_table_uid()'s fallback instead of asserting it
    -- holds a table. One unsatisfiable assert makes every
    -- question about the trace pair answer "unsat".
    local tab_id = ir_node.get_table_uid(raw_cell)
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.TAB, tab_id)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
