local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')
local op_type = require('ljopt.ir.op_type')

local impls = {}

impls.IRNodeSLOADNum = {}
ir_node.extended(impls.IRNodeSLOADNum, ir_node.ir_node_base)

function impls.IRNodeSLOADNum:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local data = ctx.vm_stack:load(slot, self:get_type())
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, self:get_type(), data)
    )
end

impls.IRNodeSLOADInt = {}
ir_node.extended(impls.IRNodeSLOADInt, ir_node.ir_node_base)

function impls.IRNodeSLOADInt:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local data = ctx.vm_stack:load(slot, self:get_type())
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, self:get_type(), data)
    )
end

impls.IRNodeSLOADTab = {}
ir_node.extended(impls.IRNodeSLOADTab, ir_node.ir_node_base)

function impls.IRNodeSLOADTab:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local ssa_ref = self:get_ssa_reference()
    local mem_slot, smt_fm = ctx.mem_stack:allocate(slot)
    ctx.tab_info[ssa_ref] = {mem_ref = mem_slot}
    return ('%s\n%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, 'i64',
            arith_utils.const_int_to_smt_bv(mem_slot)
        ),
        smt_fm
    )
end

impls.IRNodeSLOADCdt = {}
ir_node.extended(impls.IRNodeSLOADCdt, ir_node.ir_node_base)

function impls.IRNodeSLOADCdt:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local ssa_ref = self:get_ssa_reference()
    local mem_slot, smt_fm = ctx.mem_stack:allocate(slot)
    ctx.tab_info[ssa_ref] = {mem_ref = mem_slot}
    return ('%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        smt_fm
    )
end

local function bool_constant_to_smt_lib(self, ctx)
    local ssa_ref = self:get_ssa_reference()
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, 'i64', self.hex_constant)
    )
end

impls.IRNodeSLOADTru = {}
ir_node.extended(impls.IRNodeSLOADTru, ir_node.ir_node_base)
impls.IRNodeSLOADTru.hex_constant = '#xFFFFFFFD00000000'
impls.IRNodeSLOADTru.to_smt_lib = bool_constant_to_smt_lib

impls.IRNodeSLOADFal = {}
ir_node.extended(impls.IRNodeSLOADFal, ir_node.ir_node_base)
impls.IRNodeSLOADFal.hex_constant = '#xFFFFFFFE00000000'
impls.IRNodeSLOADFal.to_smt_lib = bool_constant_to_smt_lib

impls.IRNodeSLOADStr = {}
ir_node.extended(impls.IRNodeSLOADStr, ir_node.ir_node_base)

function impls.IRNodeSLOADStr:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local ssa_ref = self:get_ssa_reference()
    local data = ctx.vm_stack:load(slot, op_type.STR)
    return ('%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.STR, data)
    )
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
