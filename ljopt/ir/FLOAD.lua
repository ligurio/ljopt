local ffi = require('ffi')

local ir_node = require('ljopt.ir.ir_node_base')

local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')
local smt_constants = require('ljopt.smt_constants')

local impls = {}

impls.IRNodeFLOADNum = {}
ir_node.extended(impls.IRNodeFLOADNum, ir_node.ir_node_base)

function impls.IRNodeFLOADNum:to_smt_lib(ctx)
    local left_op
    local right_op = self:get_right_op()
    local data = ''

    -- TODO: Support other fields.
    -- TODO: cdata.type can have different IR type?
    if self:get_left_op() == 'nil' then
        -- Predefined constants.
        -- Offset may be different depending on platform.
        -- on x86-64 it's correct.
        -- Apparently whether they differ depends only
        -- on value of LUAJIT_ENABLE_GC64.
        -- Note: That's all constants we need. Other
        -- constants appear only in asm.
        if ffi.abi('gc64') then
            if right_op == '#306' then
                data = ir_node.retrieve_num_op(
                    '#x8000000000000000', ctx, self:get_type()
                )
            elseif right_op == '#302' then
                data = ir_node.retrieve_num_op(
                    '#x7fffffffffffffff', ctx, self:get_type()
                )
            else
                assert(false,
                    'Unreachable. Other constants should not be here.'
                )
            end
        else
            if right_op == '#226' then
                data = ir_node.retrieve_num_op(
                    '#x8000000000000000', ctx, self:get_type()
                )
            elseif right_op == '#222' then
                data = ir_node.retrieve_num_op(
                    '#x7fffffffffffffff', ctx, self:get_type()
                )
            else
                assert(false,
                    'Unreachable. Other constants should not be here.'
                )
            end
        end
    end
    if right_op == 'cdata.int64' then
        left_op = ir_node.retrieve_i64_op(
            self:get_left_op(), ctx, self:get_type()
        )
        data = left_op
    end
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeFLOADInt = {}
ir_node.extended(impls.IRNodeFLOADInt, ir_node.ir_node_base)

function impls.IRNodeFLOADInt:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local data = ''
    if right_op == 'str.len' then
        if left_op ~= nil and string.sub(left_op, 1, 1) == '"' then
            -- If right argument is a constant string.
            assert(string.sub(left_op, -1) == '"')
            assert(type(left_op) == 'string')
            local len = #left_op - 2
            data = arith_utils.const_int_to_smt_bv(len)
        else
            utils.unreachable('str.len: left operand is not a string literal')
        end
    elseif right_op:sub(1, 3) == 'tab' then
        -- Loads tab.hmask, tab.asize, etc.
        local field_hash = tostring(
            utils.hash(smt_constants.FIELD_TAB_PREFIX .. right_op)
        )
        assert(tonumber(left_op) ~= nil, left_op)
        local tab_left = ctx.tab_info[tonumber(left_op)].mem_ref
        data = ctx.mem_stack:load_index(tonumber(tab_left), field_hash)
    else
        utils.unreachable('FLOADInt: unsupported right_op: ' .. right_op)
    end
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end


impls.IRNodeFLOADTab = {}
ir_node.extended(impls.IRNodeFLOADTab, ir_node.ir_node_base)

function impls.IRNodeFLOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local ssa_ref = self:get_ssa_reference()
    if right_op == 'tab.meta' then
        -- Left operand contains table, load it.
        local left_slot = tonumber(left_op)
        local table_info = ctx.tab_info[left_slot]
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
        utils.unreachable('FLOADTab: unsupported right_op: ' .. right_op)
    end
end

impls.IRNodeFLOADP32 = {}
ir_node.extended(impls.IRNodeFLOADP32, ir_node.ir_node_base)

function impls.IRNodeFLOADP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    if left_op:sub(1, 1) == "{" then
        utils.unreachable('FLOADP32: constant table left_op not yet supported')
    end
    local right_op = self:get_right_op()

    if right_op == 'tab.node' or right_op == 'tab.array' then
        -- Forward id of table
        ctx.tab_info[self:get_ssa_reference()] = ctx.tab_info[tonumber(left_op)]
        return '; Nothing to do '
    else
        utils.unreachable('FLOADP32: unsupported right_op: ' .. right_op)
    end
end

function impls.IRNodeFLOADInt.is_implemented(_flags, _type, _opcode,
                                              left_op, right_op)
    if (right_op == 'tab.amask' or
       right_op == 'tab.hmask' or
       right_op == 'str.len') and left_op:sub(1, 1) ~= "{"
    then
        return true
    end
    return false
end

function impls.IRNodeFLOADTab.is_implemented(_flags, _type, _opcode,
                                              _left_op, _right_op)
    return false
end

function impls.IRNodeFLOADP32.is_implemented(_flags, _type, _opcode,
                                              left_op, right_op)
    if (right_op == 'tab.node' or right_op == 'tab.array')
        -- FLOAD from constant is not supported yet.
        -- Constant tables can be optimized, so we have to take
        -- into account it's content, which can be recursive.
        and left_op:sub(1, 1) ~= "{" then
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
