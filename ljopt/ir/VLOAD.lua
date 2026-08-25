-- Reads one slot of the vararg region: `VLOAD <aref>`.
--
-- The AREF in front of it names (vararg region, index) the same
-- way an AREF over a table names (table, key), so this is ALOAD
-- on that region. The region is one shared object tied to the
-- base memory, so both traces read the varargs they were both
-- entered with.
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

local function typed_load(smt_type, tester)
    return function(self, ctx)
        local tab_left, idx_left, raw_cell =
            ir_node.retrieve_tab_ref(self:get_left_op(), ctx)
        local ssa_ref = self:get_ssa_reference()
        return ('%s\n%s'):format(
            ctx.te_stack:store(ssa_ref, (tester):format(raw_cell)),
            ctx.op_stack:store(ssa_ref, smt_type,
                ctx.mem_stack:load_index(tab_left, idx_left, smt_type)
            )
        )
    end
end

impls.IRNodeVLOADNum = {}
ir_node.extended(impls.IRNodeVLOADNum, ir_node.ir_node_base)
impls.IRNodeVLOADNum.to_smt_lib =
    typed_load(op_type.NUM, '((_ is fp-val) %s)')

impls.IRNodeVLOADStr = {}
ir_node.extended(impls.IRNodeVLOADStr, ir_node.ir_node_base)
impls.IRNodeVLOADStr.to_smt_lib =
    typed_load(op_type.STR, '((_ is str-val) %s)')

impls.IRNodeVLOADInt = {}
ir_node.extended(impls.IRNodeVLOADInt, ir_node.ir_node_base)
impls.IRNodeVLOADInt.to_smt_lib =
    typed_load(op_type.INT, '((_ is int-val) %s)')

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
