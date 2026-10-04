local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSWAPInt = {}
ir_node.extended(impls.IRNodeBSWAPInt, ir_node.ir_node_base)

function impls.IRNodeBSWAPInt:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, self:get_type()
    )
    -- Swaps bytes 0 1 2 3 -> 3 2 1 0 in 32-bit bitvector.
    local bswap = [[
(concat
  (concat (concat ((_ extract 7 0) x) ((_ extract 15 8) x))
          ((_ extract 23 16) x))
  ((_ extract 31 24) x)
)
]]
    local data = ('(let ((x %s)) ((_ sign_extend 32) %s))'):format(
        left_op, bswap
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeBSWAPI64 = {}
ir_node.extended(impls.IRNodeBSWAPI64, ir_node.ir_node_base)

function impls.IRNodeBSWAPI64:to_smt_lib(ctx)
    local left_op = ir_node.retrieve_i64_op(
        self:get_left_op(), ctx, self:get_type()
    )
    local bytes = {}
    for i = 0, 7 do
        bytes[#bytes + 1] = ('((_ extract %d %d) x)'):format(8 * i + 7, 8 * i)
    end
    local data = ('(let ((x %s)) (concat %s))'):format(
        left_op, table.concat(bytes, ' ')
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
