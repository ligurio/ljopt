local ir_node = require('ljopt.ir.ir_node_base')
local arith_utils = require('ljopt.ir.arith_utils')
local ljopt_config = require('ljopt.config')
local op_type = require('ljopt.ir.op_type')

local function init_const_tab(ctx, slot)
    local ct = ctx.const_tabs_by_slot[slot]
    if ct == nil then
        ct = {content = {}, fields = {}}
        ctx.const_tabs_by_slot[slot] = ct
    end
    return ct
end

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
    local ssa_ref = self:get_ssa_reference()
    -- Load the slot as NUM (not INT) so a narrowed `SLOAD int`
    -- reads the same fp value the corresponding `SLOAD num`
    -- would, then convert it back to int32.
    local fp_data = ctx.vm_stack:load(slot, op_type.NUM)
    local data = arith_utils.smt_fp_to_int(fp_data)
    -- C flag (SLOAD mode) = FORL narrowing: num->int32 conv.
    local mode = self:get_right_op() and self:get_right_op():get_lit() or ''
    local prefix = ''
    if mode:find('C', 1, true) and ljopt_config.is_narrowing() then
        -- Roundtrip integrality (input is exactly int32).
        prefix = (
            '(assert (= %s ((_ to_fp 11 53) RTZ %s)))\n' ..
            '(assert (not (and (fp.isZero %s) (fp.isNegative %s))))\n'
        ):format(fp_data, data, fp_data, fp_data)
    end
    return ('%s%s\n%s'):format(
        prefix,
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
    ctx.const_tabs[ssa_ref] = init_const_tab(ctx, slot)
    return ('%s\n%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.TAB, tostring(mem_slot)),
        smt_fm
    )
end

impls.IRNodeSLOADCdt = {}
ir_node.extended(impls.IRNodeSLOADCdt, ir_node.ir_node_base)

function impls.IRNodeSLOADCdt:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local ssa_ref = self:get_ssa_reference()
    local mem_slot, smt_fm = ctx.mem_stack:allocate(slot)
    ctx.const_tabs[ssa_ref] = init_const_tab(ctx, slot)
    return ('%s\n%s\n%s'):format(
        -- I suppose guard for SLOAD is always true for us.
        -- It means we never exit by it.
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, 'cdt',
            arith_utils.const_int_to_smt_bv(tonumber(mem_slot))
        ),
        smt_fm
    )
end

impls.IRNodeSLOADFun = {}
ir_node.extended(impls.IRNodeSLOADFun, ir_node.ir_node_base)

function impls.IRNodeSLOADFun:to_smt_lib(ctx)
    local slot = ir_node.retrieve_slot_op(self:get_left_op())
    local ssa_ref = self:get_ssa_reference()
    local mem_slot, smt_fm = ctx.mem_stack:allocate(slot)
    ctx.const_tabs[ssa_ref] = init_const_tab(ctx, slot)
    return ('%s\n%s\n%s'):format(
        ctx.te_stack:store(ssa_ref, 'true'),
        ctx.op_stack:store(ssa_ref, op_type.TAB, tostring(mem_slot)),
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
