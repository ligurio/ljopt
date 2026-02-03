local ffi = require('ffi')

local ir_node = require('ljopt.ir.ir_node_base')

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

    -- We can't say anything, never-fail will be refactored and
    -- we'll be able to mark not implemented parts of node.
    -- Finally when everything is implemented this case
    -- will be eliminated. 
    data = string.format("#x%s", bit.tohex(0, 16))

    if right_op == 'str.len' then
        if left_op ~= nil and string.sub(left_op, 1, 1) == '"' then
            assert(string.sub(str, -1) == '"')
            assert(type(left_op) == 'string')
            local len = #left_op - 2
            data = string.format("#x%s", bit.tohex(len, 16))
        end
    elseif right_op == 'tab.hmask' then
        if left_type == 'op' then
            local left_node = ctx.cur_nodes[tonumber(left_op)]
            if left_node:get_opcode() == 'SLOAD' then
                data = ir_node.retrieve_i64_op(
                    left_op, ctx, self:get_type()
                )
                data = "(bvand " .. data .. " #x0000000011111111)"
            elseif left_node:get_opcode() == 'TNEW' then
                assert(false)
            elseif left_node:get_opcode() == 'TDUP' then
                assert(false)
            else 
                assert(false)
            end
        else
            assert(false)
        end        
    elseif right_op == 'tab.amask' then
        if left_type == 'op' then
            local left_node = ctx.cur_nodes[tonumber(left_op)]
            if left_node:get_opcode() == 'SLOAD' then
                local data = ir_node.retrieve_i64_op(
                    left_op, ctx, self:get_type()
                )
                data = "(bvashr " .. data .. " 4)"
            elseif left_node:get_opcode() == 'TNEW' then
                assert(false)
            elseif left_node:get_opcode() == 'TDUP' then
                assert(false)
            else
                assert(false)
            end
        else
            assert(false)
        end
    else
        assert(false)
    end
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
