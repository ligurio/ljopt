local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local smt_constants = require('ljopt.smt_constants')

local impls = {}

-- p32 FREF <tab> <field>
--
-- A "pointer" to a named GCobj field of a table (func.env,
-- tab.meta, tab.array, tab.node, ...). The address is encoded
-- exactly like the p32 produced by HREFK: a `p32-val` MemCell
-- whose first component is the table's memory pointer and whose
-- second component is the reserved field index. FSTORE is the
-- only consumer; it decodes the address via retrieve_tab_ref.
impls.IRNodeFREFP32 = {}
ir_node.extended(impls.IRNodeFREFP32, ir_node.ir_node_base)

function impls.IRNodeFREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local field = right_op:get_lit()
    local tab_ssa = left_op:get_ssa()
    local tab_id = ctx.op_stack:load(tab_ssa, op_type.TAB)
    local idx = arith_utils.const_str_to_memcell(
        smt_constants.FIELD_TAB_PREFIX .. field
    )
    local p32 = ir_node.make_tab_ref(tab_id, idx)
    return ctx.op_stack:store(self:get_ssa_reference(), op_type.ANY, p32)
end

function impls.IRNodeFREFP32.is_implemented(_flags, _type, _opcode,
                                             left_op, right_op)
    return left_op ~= nil and left_op:is_ssa()
        and right_op ~= nil and right_op:is_lit()
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
