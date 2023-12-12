local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_CONV = {}
ir_node.extended(ir_node_CONV, ir_node.ir_node_base)

function ir_node_CONV:to_smt_lib(ctx)
    local left_op = ''
    local right_op = self:get_right_op()
    local data = ''

    -- TODO: Support other conversions
    if right_op == "num.int" then
        left_op = self:retrieve_int_op(self:get_left_op(), ctx)
        left_op = left_op:gsub("+", "")
        data = string.format("((_ to_fp 11 53) roundNearestTiesToEven %s 0.)", left_op)
    elseif right_op == "int.num" then
        left_op = self:retrieve_num_op(self:get_left_op(), ctx)
        -- TODO handle inputs that are out of range 
        data = string.format("((_ fp.to_sbv 32) roundNearestTiesToEven %s)", left_op)
    elseif right_op == "num.i64" then
        left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
        -- TODO recheck rounding behaviour
        data = string.format("((_ to_fp 11 53) roundNearestTiesToEven %s 0.)", left_op)
    elseif right_op == "i64.num" then
        left_op = self:retrieve_num_op(self:get_left_op(), ctx)
        -- TODO handle inputs that are out of range 
        data = string.format("((_ fp.to_sbv 64) roundNearestTiesToEven %s)", left_op)
    else
        assert(false, "Unsupported type conversion")
    end

    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

function instance(ssa_ref, flags, type, left_op, right_op)
    return ir_node_CONV:new(ssa_ref, flags, type, "CONV", left_op, right_op)
end

return {
    instance = instance
}
