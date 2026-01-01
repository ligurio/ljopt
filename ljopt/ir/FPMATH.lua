local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeFPMATHNum = {}
ir_node.extended(impls.IRNodeFPMATHNum, ir_node.ir_node_base)


function impls.IRNodeFPMATHNum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:get_right_op()
    local ssa_ref = self:get_ssa_reference()
    local type = self:get_type()
    if right_op == 'floor' then
        local data = ('(fp.roundToIntegral RTN %s)'):format(left_op)
        return ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'ceil' then
        local data = ('(fp.roundToIntegral RTP %s)'):format(left_op)
        return ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'trunc' then
        local data = ('(fp.roundToIntegral RTZ %s)'):format(left_op)
        return ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'sqrt' then
        local data = ('(fp.sqrt RNE %s)'):format(left_op)
        return ctx.op_stack:store(ssa_ref, type, data)
    elseif right_op == 'exp' then
        assert(false, 'No simple way to implement exp.')
    elseif right_op == 'exp2' then
        assert(false, 'No simple way to implement exp2.')
    elseif right_op == 'log' then
        assert(false, 'No simple way to implement log.')
    elseif right_op == 'log2' then
        assert(false, 'No simple way to implement log2.')
    elseif right_op == 'log10' then
        assert(false, 'No simple way to implement log10.')
    elseif right_op == 'sin' then
        assert(false, 'No simple way to implement sin.')
    elseif right_op == 'cos' then
        assert(false, 'No simple way to implement cos.')
    elseif right_op == 'tan' then
        assert(false, 'No simple way to implement tan.')
    else
        assert("This OP do not exists in LuaJIT " .. right_op)
    end
end

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    return impls[node_str]:new(
        ssa_ref, flags, type, 'FPMATH', left_op, right_op
    )
end

return {
    instance = instance
}
