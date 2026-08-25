-- Reads the upvalue a UREF names. The reference is an (object,
-- key) pair like an HREFK's, so this is HLOAD on the closure.
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

local function typed_load(smt_type, tester)
    return function(self, ctx)
        local tab_left, idx_left, raw_cell =
            ir_node.retrieve_tab_ref(self:get_left_op(), ctx)
        local ssa_ref = self:get_ssa_reference()
        local guard = tester and (tester):format(raw_cell) or 'true'
        return ('%s\n%s'):format(
            ctx.te_stack:store(ssa_ref, guard),
            ctx.op_stack:store(ssa_ref, smt_type,
                ctx.mem_stack:load_index(tab_left, idx_left, smt_type)
            )
        )
    end
end

impls.IRNodeULOADNum = {}
ir_node.extended(impls.IRNodeULOADNum, ir_node.ir_node_base)
impls.IRNodeULOADNum.to_smt_lib =
    typed_load(op_type.NUM, '((_ is fp-val) %s)')

impls.IRNodeULOADStr = {}
ir_node.extended(impls.IRNodeULOADStr, ir_node.ir_node_base)
impls.IRNodeULOADStr.to_smt_lib =
    typed_load(op_type.STR, '((_ is str-val) %s)')

impls.IRNodeULOADInt = {}
ir_node.extended(impls.IRNodeULOADInt, ir_node.ir_node_base)
impls.IRNodeULOADInt.to_smt_lib =
    typed_load(op_type.INT, '((_ is int-val) %s)')

-- A cell holding no table is a state the trace can be in, so the
-- id is decoded with get_table_uid()'s fallback rather than
-- asserted -- one unsatisfiable assert answers every question
-- about the pair with "unsat", which reads as "equivalent".
impls.IRNodeULOADTab = {}
ir_node.extended(impls.IRNodeULOADTab, ir_node.ir_node_base)

function impls.IRNodeULOADTab:to_smt_lib(ctx)
    local _, _, raw_cell = ir_node.retrieve_tab_ref(self:get_left_op(), ctx)
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(
            ssa_ref, op_type.TAB, ir_node.get_table_uid(raw_cell)
        )
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
