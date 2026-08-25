-- Reference to an upvalue: `UREFC fn, #0` (closed) and its open
-- counterpart UREFO.
--
-- An upvalue has no VM slot of its own, but the closure holding
-- it does -- SLOAD gives that a slot-derived memory id both
-- traces agree on. So an upvalue is modelled as a field of the
-- closure, named by its index, and the reference is the same
-- (object, key) p32 pair AREF and HREFK build.
local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local smt_constants = require('ljopt.smt_constants')

local impls = {}

local IRNodeUREF = {}
ir_node.extended(IRNodeUREF, ir_node.ir_node_base)

function IRNodeUREF:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local ssa_ref = self:get_ssa_reference()
    local fn_ssa = left_op:get_ssa()
    local key = arith_utils.const_str_to_memcell(
        ('%suv.%d'):format(
            smt_constants.FIELD_TAB_PREFIX,
            ir_node.retrieve_slot_op(self:get_right_op())
        )
    )
    ctx.const_tabs[ssa_ref] = ctx.const_tabs[fn_ssa]
    local fn_id = ctx.op_stack:load(fn_ssa, op_type.TAB)
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(
            ssa_ref, op_type.ANY, ir_node.make_tab_ref(fn_id, key)
        )
    )
end

-- A UREFO on a constant function has no op-stack entry to read
-- the closure out of, and the aliasing guards around it need a
-- p32 SUB against REF_BASE that is not modelled either.
function IRNodeUREF.is_implemented(_flags, _type, _opcode,
                                   left_op, right_op_val)
    return left_op ~= nil and left_op:is_ssa()
        and right_op_val ~= nil and right_op_val:is_imm()
end

impls.IRNodeUREFCP32 = IRNodeUREF
impls.IRNodeUREFOP32 = IRNodeUREF

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
