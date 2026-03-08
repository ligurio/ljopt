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
            data = arith_utils.const_i64_to_smt_bv(#left_op:get_str())
        else
            data = ('((_ int2bv %d) (str.len %s))'):format(
                64,
                ctx.op_stack:load(left_op:get_ssa(), op_type.STR)
            )
        end
    elseif right_op:sub(1, 3) == 'tab' then
        -- Loads tab.hmask, tab.asize, etc.
        local field_hash = arith_utils.const_str_to_memcell(
            smt_constants.FIELD_TAB_PREFIX .. right_op
        )
        local tab_left = ctx.tab_info[left_op:get_ssa()].mem_ref
        data = ctx.mem_stack:load_index(
            tonumber(tab_left), field_hash, op_type.INT
        )
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
            -- Table pointer. Compile time.
            local tab_left = ctx.tab_info[left_op:get_ssa()].mem_ref
            -- Table index. Runtime.
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


impls.IRNodeFLOADTab = {}
ir_node.extended(impls.IRNodeFLOADTab, ir_node.ir_node_base)

function impls.IRNodeFLOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local right_op_str = ir_node.OpType.to_string(right_op)
    local ssa_ref = self:get_ssa_reference()
    if right_op_str == 'tab.meta' then
        -- Left operand contains table, load it.
        local table_info = ctx.tab_info[left_op:get_ssa()]
        assert(table_info.mem_ref ~= nil)
        local result = nil
        if table_info.meta == nil then
            table_info.meta, result = ctx.mem_stack:allocate_child(
                ssa_ref, table_info.mem_ref, "__metatable"
            )
        end
        ctx.tab_info[ssa_ref] = {
            mem_ref = table_info.meta,
            meta = nil,
        }
        if result then
            return result
        else
            return '; ' .. table_info.mem_ref .. ' to ' .. table_info.meta
        end
    else
        utils.unreachable('FLOADTab: unsupported right_op: ' .. right_op_str)
    end
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
        -- Forward id of table
        assert(left_op:is_ssa())
        ctx.tab_info[self:get_ssa_reference()] = ctx.tab_info[left_op:get_ssa()]
        return '; Nothing to do '
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
                                              _left_op, _right_op)
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
