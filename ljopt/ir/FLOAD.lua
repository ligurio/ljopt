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
    local left_type = ir_node.parse_op(left_op)
    local right_op = self:get_right_op()
    -- Dirty way to check if argument is a string.
    local is_new = ctx.cur_trace

    if right_op == 'str.len' then
        if left_op ~= nil and string.sub(left_op, 1, 1) == '"' then
            assert(string.sub(str, -1) == '"')
            assert(type(left_op) == 'string')
            local len = #left_op - 2
            data = arith_utils.const_to_smt_bv(len)
        else
            assert(false)
        end
    elseif right_op:sub(1, 3) == 'tab' then
        local idx = utils.tabfield_to_subslot(right_op)
        assert(tonumber(left_op) ~= nil, left_op)
        local tab_left = ctx.tab_info[tonumber(left_op)].mem_ref
        data = ctx.mem_stack:load_index(tonumber(tab_left), idx)
    else
        assert(false, right_op)
    end
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end


impls.IRNodeFLOADTab = {}
ir_node.extended(impls.IRNodeFLOADTab, ir_node.ir_node_base)

function impls.IRNodeFLOADTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local left_type = ir_node.parse_op(left_op)
    local right_op = self:get_right_op()

    local ssa_ref = self:get_ssa_reference()
    if right_op == 'tab.meta' then
        -- Left operand contains table, load it.
        local left_slot = tonumber(left_op)
        local table_info = ctx.tab_info[left_slot]
        assert(table_info.mem_ref ~= nil)
        local result = nil
        if table_info.meta == nil then
            table_info.meta, result = ctx.mem_stack:allocate_child(table_info.mem_ref, "__metatable")
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
        assert(false, right_op)
    end
end

impls.IRNodeFLOADP32 = {}
ir_node.extended(impls.IRNodeFLOADP32, ir_node.ir_node_base)

function impls.IRNodeFLOADP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    if left_op:sub(1, 1) == "{" then
        assert(false, 'not supported yet')
    end
    local left_type = ir_node.parse_op(left_op)
    local right_op = self:get_right_op()

    local ssa_ref = self:get_ssa_reference()
    if right_op == 'tab.node' then
        -- Forward id of table
        ctx.tab_info[self:get_ssa_reference()] = ctx.tab_info[tonumber(left_op)]
        return '; Nothing to do '
    else
        assert(false, right_op)
    end
end

-- local function impls.IRNodeFLOADP32:to_smt_lib(ctx)
--     if right_op == 'tab.meta' then
--         data = ir_node.retrieve_table_op(
--             left_op, ctx, self:get_type(), smt_constants.TAB_OFFSETS.meta
--         )
--     elseif right_op == 'tab.array' then
--         data = ir_node.retrieve_i64_op(
--             left_op, ctx, self:get_type(), smt_constants.TAB_OFFSETS.array
--         )
--     elseif right_op == 'tab.node' then
--         data = ir_node.retrieve_i64_op(
--             left_op, ctx, self:get_type(), smt_constants.TAB_OFFSETS.node
--         )
--     elseif right_op == 'tab.asize' then
--         data = ir_node.retrieve_i64_op(
--             left_op, ctx, self:get_type(), smt_constants.TAB_OFFSETS.asize
--         )
--     elseif right_op == 'tab.hmask' then
--         data = ir_node.retrieve_i64_op(
--             left_op, ctx, self:get_type(), smt_constants.TAB_OFFSETS.hmask
--         )
--     elseif right_op == 'tab.nomm' then
--         data = ir_node.retrieve_i64_op(
--             left_op, ctx, self:get_type(), smt_constants.TAB_OFFSETS.nomm
--         )
--     else
-- end


function impls.IRNodeFLOADInt.is_implemented(_flags, _type, _opcode,
                                              left_op, right_op)
    if right_op == 'str.len' then
        return true
    end
    -- -- Ignore such tables for now:
    -- -- int FLOAD {0x405f0400} tab.hmask
    -- if (right_op == 'tab.amask' or
    --    right_op == 'tab.hmask') and tonumber(left_op) ~= nil then
    --     return true
    -- end
    return false
end

function impls.IRNodeFLOADTab.is_implemented(_flags, _type, _opcode,
                                              _left_op, right_op)
    if right_op == 'tab.meta' then
        return true
    end
    return false
end

function impls.IRNodeFLOADP32.is_implemented(_flags, _type, _opcode,
                                              _left_op, right_op)
    if right_op == 'tab.node' then
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
