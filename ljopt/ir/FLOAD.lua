local ffi = require('ffi')

local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeFLOAD = {}
ir_node.extended(IRNodeFLOAD, ir_node.ir_node_base)

function IRNodeFLOAD:to_smt_lib(ctx)
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
                data = self:retrieve_num_op('#x8000000000000000', ctx)
            elseif right_op == '#302' then
                data = self:retrieve_num_op('#x7fffffffffffffff', ctx)
            else
                assert(false,
                    'Unreachable. Other constants should not be here.'
                )
            end
        else
            if right_op == '#226' then
                data = self:retrieve_num_op('#x8000000000000000', ctx)
            elseif right_op == '#222' then
                data = self:retrieve_num_op('#x7fffffffffffffff', ctx)
            else
                assert(false,
                    'Unreachable. Other constants should not be here.'
                )
            end
        end
    end
    if right_op == 'cdata.int64' then
        left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
        data = left_op
    end
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeFLOAD:new(ssa_ref, flags, type, 'FLOAD', left_op, right_op)
end

return {
    instance = instance
}
