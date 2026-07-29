local ffi = require('ffi')

local ir_node = require('ljopt.ir.ir_node_base')

local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')
local op_type = require('ljopt.ir.op_type')
local smt_constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeFLOADNum = {}
ir_node.extended(impls.IRNodeFLOADNum, ir_node.ir_node_base)

function impls.IRNodeFLOADNum:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local left_op_str = op_type.to_string(left_op)
    local right_op_str = op_type.to_string(right_op)
    local data = ''

    -- TODO: Support other fields.
    -- TODO: cdata.type can have different IR type?
    if left_op_str == 'nil' then
        -- Predefined constants.
        -- Offset may be different depending on platform.
        -- on x86-64 it's correct.
        -- Apparently whether they differ depends only
        -- on value of LUAJIT_ENABLE_GC64.
        -- Note: That's all constants we need. Other
        -- constants appear only in asm.
        if ffi.abi('gc64') then
            if right_op_str == '#306' then
                data = '((_ to_fp 11 53) #x8000000000000000)'
            elseif right_op_str == '#302' then
                data = '((_ to_fp 11 53) #x7fffffffffffffff)'
            else
                assert(false,
                    'Unreachable. Other constants should not be here.'
                )
            end
        else
            if right_op_str == '#226' then
                data = '((_ to_fp 11 53) #x8000000000000000)'
            elseif right_op_str == '#222' then
                data = '((_ to_fp 11 53) #x7fffffffffffffff)'
            else
                assert(false,
                    'Unreachable. Other constants should not be here.'
                )
            end
        end
    elseif right_op_str == 'cdata.int64' then
        data = ir_node.retrieve_i64_op(left_op, ctx, self:get_type())
    end
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeFLOADInt = {}
ir_node.extended(impls.IRNodeFLOADInt, ir_node.ir_node_base)

function impls.IRNodeFLOADInt:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op():get_lit()
    local data = ''
    if right_op == 'str.len' then
        if left_op:is_str() then
            -- If right argument is a constant string.
            local len = #left_op:get_str()
            data = arith_utils.const_i64_to_smt_bv(len)
            ctx.const_nums[self:get_ssa_reference()] = len
        else
            -- Propagate len when the SSA string was tracked as
            -- a known constant via HSTORE->HLOAD chains.
            local known = ctx.const_strs[left_op:get_ssa()]
            if known ~= nil then
                local len = #known
                data = arith_utils.const_i64_to_smt_bv(len)
                ctx.const_nums[self:get_ssa_reference()] = len
            else
                data = ('((_ int2bv %d) (str.len %s))'):format(
                    64,
                    ctx.op_stack:load(left_op:get_ssa(), op_type.STR)
                )
            end
        end
    elseif right_op:sub(1, 3) == 'tab' then
        -- Loads tab.hmask, tab.asize, etc.
        local field_hash = arith_utils.const_str_to_memcell(
            smt_constants.FIELD_TAB_PREFIX .. right_op
        )
        local ct = ctx.const_tabs[left_op:get_ssa()]
        local tab_left = ctx.op_stack:load(left_op:get_ssa(), op_type.TAB)
        data = ctx.mem_stack:load_index(tab_left, field_hash, op_type.INT)
        -- Propagate constant table metadata for const-folding.
        if ct ~= nil then
            if right_op == 'tab.asize' and ct.asize ~= nil then
                ctx.const_nums[self:get_ssa_reference()] = ct.asize
            elseif right_op == 'tab.hmask' and ct.hmask ~= nil then
                ctx.const_nums[self:get_ssa_reference()] = ct.hmask
            end
        end
    else
        utils.unreachable('FLOADInt: unsupported right_op: ' .. right_op)
    end
    return ctx.op_stack:store(self:get_ssa_reference(), op_type.INT, data)
end

impls.IRNodeFLOADI64 = {}
ir_node.extended(impls.IRNodeFLOADI64, ir_node.ir_node_base)

function impls.IRNodeFLOADI64:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local right_op_str = op_type.to_string(right_op)
    local data = ''
    if right_op_str == 'cdata.int64' then
        if left_op:is_i64() then
            data = arith_utils.const_i64_to_smt_bv(left_op:get_i64())
        elseif left_op:is_ssa() then
            local tab_left = ctx.op_stack:load(left_op:get_ssa(), 'cdt')
            local idx_left = arith_utils.const_str_to_memcell(
                smt_constants.FIELD_TAB_PREFIX .. 'cdata.value'
            )
            data = ctx.mem_stack:load_index(tab_left, idx_left, op_type.I64)
        else
            utils.unreachable(
                'Unsupported left_op: ' .. left_op.type ..
                ' ' .. op_type.to_string(left_op)
            )
        end
    else
        utils.unreachable('FLOADI64: unsupported right_op: ' .. right_op_str)
    end
    return ctx.op_stack:store(self:get_ssa_reference(), op_type.I64, data)
end


impls.IRNodeFLOADU32 = {}
ir_node.extended(impls.IRNodeFLOADU32, ir_node.ir_node_base)

-- Reads the scalar value out of a cdata box as an unsigned 32-bit
-- integer (e.g. `ffi.cast("uint32_t", x)` boxes). Mirrors
-- IRNodeFLOADI64's `cdata.value` access, then canonicalizes to a
-- zero-extended u32.
function impls.IRNodeFLOADU32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op_str = op_type.to_string(self:get_right_op())
    local data = ''
    if right_op_str == 'cdata.int' then
        if left_op:is_ssa() then
            local tab_left = ctx.op_stack:load(left_op:get_ssa(), 'cdt')
            local idx_left = arith_utils.const_str_to_memcell(
                smt_constants.FIELD_TAB_PREFIX .. 'cdata.value'
            )
            data = arith_utils.wrap_u32(
                ctx.mem_stack:load_index(tab_left, idx_left, op_type.I64)
            )
        else
            utils.unreachable(
                'FLOADU32: unsupported left_op: ' .. left_op.type
            )
        end
    else
        utils.unreachable('FLOADU32: unsupported right_op: ' .. right_op_str)
    end
    return ctx.op_stack:store(self:get_ssa_reference(), 'u32', data)
end

function impls.IRNodeFLOADU32.is_implemented(_flags, _type, _opcode,
                                             left_op, right_op_val)
    return op_type.to_string(right_op_val) == 'cdata.int' and left_op:is_ssa()
end

impls.IRNodeFLOADTab = {}
ir_node.extended(impls.IRNodeFLOADTab, ir_node.ir_node_base)

function impls.IRNodeFLOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local right_op_str = op_type.to_string(right_op)
    local ssa_ref = self:get_ssa_reference()

    if right_op_str ~= 'tab.meta' and right_op_str ~= 'func.env' then
        utils.unreachable('FLOADTab: unsupported right_op: ' .. right_op_str)
    end

    -- Share const_tabs across aliased FLOADs of the same
    -- sub-table (e.g., two FLOADTab `func.env` from the same
    -- SLOAD both reach the same env-table dict).
    local parent_ssa = left_op:get_ssa()
    if ctx.const_tabs[parent_ssa] == nil then
        ctx.const_tabs[parent_ssa] = {content = {}, fields = {}}
    end
    local parent_ct = ctx.const_tabs[parent_ssa]
    parent_ct.fields = parent_ct.fields or {}
    if parent_ct.fields[right_op_str] == nil then
        parent_ct.fields[right_op_str] = {content = {}, fields = {}}
    end
    ctx.const_tabs[ssa_ref] = parent_ct.fields[right_op_str]

    -- Same path as HLOAD on a TAB-typed cell: read the parent's
    -- mem slot and decode the field as a tab pointer.
    local parent_ptr = ctx.op_stack:load(left_op:get_ssa(), op_type.TAB)
    local field_hash = arith_utils.const_str_to_memcell(
        smt_constants.FIELD_TAB_PREFIX .. right_op_str
    )
    local raw_cell = ('(select %s %s)'):format(
        ctx.mem_stack:load(parent_ptr), field_hash
    )
    local data = ctx.mem_stack:load_index(
        parent_ptr, field_hash, op_type.TAB
    )
    return ('(assert ((_ is tab-val) %s))\n%s'):format(
        raw_cell,
        ctx.op_stack:store(ssa_ref, op_type.TAB, data)
    )
end

impls.IRNodeFLOADP32 = {}
ir_node.extended(impls.IRNodeFLOADP32, ir_node.ir_node_base)

function impls.IRNodeFLOADP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    if left_op:is_tab() then
        utils.unreachable('FLOADP32: constant table left_op not yet supported')
    end
    local right_op = self:get_right_op()
    local right_op_str = op_type.to_string(right_op)

    if right_op_str == 'tab.node' or right_op_str == 'tab.array' then
        assert(left_op:is_ssa())
        local tab_ssa = left_op:get_ssa()
        local ssa_ref = self:get_ssa_reference()
        if ctx.const_tabs[tab_ssa] == nil then
            ctx.const_tabs[tab_ssa] = {content = {}, fields = {}}
        end
        ctx.const_tabs[ssa_ref] = ctx.const_tabs[tab_ssa]
        local tab_val = ctx.op_stack:load(tab_ssa, op_type.TAB)
        return ctx.op_stack:store(ssa_ref, op_type.TAB, tab_val)
    else
        utils.unreachable('FLOADP32: unsupported right_op: ' .. right_op_str)
    end
end

function impls.IRNodeFLOADInt.is_implemented(_flags, _type, _opcode,
                                             _left_op, right_op_val)
    -- tab.* are temporary disabled here,
    -- because we are not taking into account
    -- table/array size modification during
    -- insertions.
    -- See: https://github.com/ligurio/ljopt/issues/51
    local right_op = right_op_val:get_lit()
    if right_op == 'str.len' then
        return true
    end
    return false
end

function impls.IRNodeFLOADTab.is_implemented(_flags, _type, _opcode,
                                              _left_op, right_op_val)
    local right_op = op_type.to_string(right_op_val)
    if right_op == 'tab.meta' or right_op == 'func.env' then
        return true
    end
    return false
end

function impls.IRNodeFLOADP32.is_implemented(_flags, _type, _opcode,
                                              left_op, right_op_val)
    local right_op = op_type.to_string(right_op_val)
    if (right_op == 'tab.node' or right_op == 'tab.array')
        -- FLOAD from constant is not supported yet.
        -- Constant tables can be optimized, so we have to take
        -- into account it's content, which can be recursive.
        and not left_op:is_tab() then
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
