local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeBSWAPInt = {}
ir_node.extended(impls.IRNodeBSWAPInt, ir_node.ir_node_base)

function impls.IRNodeBSWAPInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    -- luacheck: push no max_line_length
    -- Swaps bytes 0 1 2 3 -> 3 2 1 0 in 32-bit bitvector.
    local bswap = "(concat (concat (concat ((_ extract 7 0) x) ((_ extract 15 8) x)) ((_ extract 23 16) x)) ((_ extract 31 24) x))"
    -- luacheck: pop
    local data = ('(let ((x %s)) (concat #x00000000 %s))'):format(
        left_op, bswap
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    local op_table = {
        ['int'] = '',
    }
    assert(op_table[type], 'Should not be nil.')
    local node = impls[node_str]:new(
        ssa_ref, flags, type, 'BSWAP', left_op, right_op
    )
    node.op_str = op_table[type]
    return node
end

return {
    instance = instance
}
