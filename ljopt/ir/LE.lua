local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeLEBase = {}
ir_node.extended(IRNodeLEBase, ir_node.ir_node_base)

local impls = {}

impls.IRNodeLEInt = {}
ir_node.extended(impls.IRNodeLEInt, IRNodeLEBase)

function impls.IRNodeLEInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(bvsgt %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

impls.IRNodeLENum = {}
ir_node.extended(impls.IRNodeLENum, IRNodeLEBase)

function impls.IRNodeLENum:to_smt_lib(ctx)
    local left_op = self:retrieve_num_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_num_op(self:get_right_op(), ctx)
    -- Z3 and Bitwuzla return CE if `<=` used.
    local data = string.format('(fp.leq %s %s)', left_op, right_op)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
