-- Reference to an upvalue: `UREFC fn, #0` (closed) and its open
-- counterpart UREFO.
--
-- An upvalue has no VM slot of its own, but the closure holding
-- it does -- SLOAD gives that a slot-derived memory id both
-- traces agree on. So an upvalue is modelled as a field of the
-- closure, named by its index, and the reference is the same
-- (object, key) p32 pair AREF and HREFK build.
local jutil = require('jit.util')
local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local smt_constants = require('ljopt.smt_constants')

local impls = {}

-- A closure reaches UREFO as a constant, and what is printed for
-- it is an address that differs between the two recordings. Its
-- bytecode does not: the same chunk compiled twice gives the
-- same instructions, and two different functions do not collide
-- the way their lines or shapes might.
--
-- Two closures sharing one prototype share this id. For an open
-- upvalue that costs nothing -- the id only names the guard's
-- subject, never a value -- but a closed one would alias.
local function closure_id(fn)
    local h, pc = 5381, 0
    while true do
        local ins = jutil.funcbc(fn, pc)
        if ins == nil then
            break
        end
        h = (h * 33 + ins) % 1000003
        pc = pc + 1
    end
    return 2000000 + h
end


local IRNodeUREF = {}
ir_node.extended(IRNodeUREF, ir_node.ir_node_base)

function IRNodeUREF:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local ssa_ref = self:get_ssa_reference()
    local key = arith_utils.const_str_to_memcell(
        ('%suv.%d'):format(
            smt_constants.FIELD_TAB_PREFIX,
            ir_node.retrieve_slot_op(self:get_right_op())
        )
    )
    local fn_id
    if left_op:is_fun() then
        fn_id = tostring(
            ctx.mem_stack:allocate(closure_id(left_op:get_fun()))
        )
    else
        local fn_ssa = left_op:get_ssa()
        ctx.const_tabs[ssa_ref] = ctx.const_tabs[fn_ssa]
        fn_id = ctx.op_stack:load(fn_ssa, op_type.TAB)
    end
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(
            ssa_ref, op_type.ANY, ir_node.make_tab_ref(fn_id, key)
        )
    )
end

-- UREFO on a constant closure is rejected, and not for want of a
-- name for it: its bytecode is identical in both recordings and
-- keys it fine. An *open* upvalue still lives in the VM stack,
-- and the recorder proves so with `EQ REF_BASE, uref + k` and
-- then reads the stack slot directly -- so the optimized trace
-- has a slot where this one would have an upvalue object, and
-- the two are not connected. Modelling it as its own object
-- makes equivalent traces read as different.
function IRNodeUREF.is_implemented(_flags, _type, _opcode,
                                   left_op, right_op_val)
    return left_op ~= nil and (left_op:is_ssa() or left_op:is_fun())
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
