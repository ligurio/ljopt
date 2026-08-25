-- Reference to a named field of an object: `FREF obj, tab.meta`.
--
-- The p32 it produces is what FSTORE writes through, the way an
-- HREFK is what HSTORE writes through. The field is keyed the
-- same way FLOAD reads it -- a prefixed name in the object's own
-- memory -- so a store through this reference lands in the cell
-- the matching load comes out of.
local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local smt_constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeFREFP32 = {}
ir_node.extended(impls.IRNodeFREFP32, ir_node.ir_node_base)

function impls.IRNodeFREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local ssa_ref = self:get_ssa_reference()
    local field = arith_utils.const_str_to_memcell(
        smt_constants.FIELD_TAB_PREFIX .. op_type.to_string(self:get_right_op())
    )
    local tab_id = ctx.op_stack:load(left_op:get_ssa(), op_type.TAB)
    -- Share the const-folding dictionary with the object, as
    -- HREFK does, so a field read after this store still folds.
    ctx.const_tabs[ssa_ref] = ctx.const_tabs[left_op:get_ssa()]
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(
            ssa_ref, op_type.ANY, ir_node.make_tab_ref(tab_id, field)
        )
    )
end

function impls.IRNodeFREFP32.is_implemented(_flags, _type, _opcode,
                                            left_op, _right_op_val)
    return left_op ~= nil and left_op:is_ssa()
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
