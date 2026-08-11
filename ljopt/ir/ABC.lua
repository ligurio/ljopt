-- Array bounds check.
--
-- `ABC(asize, idx)` is a guarded *unsigned* compare: the trace
-- goes on while `idx <u asize` and takes the exit otherwise. One
-- unsigned compare covers both ends of the range at once, which
-- is why the recorder emits it instead of a signed pair -- a
-- negative index wraps to a huge u32 and fails the very same
-- test.
--
-- Both operands are 32-bit integers, and the op stack holds them
-- as 64-bit vectors, so the compare extracts the low 32 bits
-- first. The other unsigned guards (ULT and friends) compare the
-- 64-bit values directly, which works only while every int in the
-- stack is a canonical sign-extension; extracting does not depend
-- on that.
--
-- An ABC produces no value, only an exit, so it writes te_stack
-- and nothing else -- and nothing can ever reference it, which is
-- why there is no const_nums entry to fold here.
--
-- The node's own type is *not* the type of its operands. The
-- recorder types the check it hoists out of a loop as p32, or as
-- u32 when the bound is a constant (rec_idx_abc in lj_record.c);
-- that is what lets the abc_invar fold rule recognize and drop
-- it. All three flavours compare the same int operands.
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

local IRNodeABCBase = {}
ir_node.extended(IRNodeABCBase, ir_node.ir_node_base)

function IRNodeABCBase:to_smt_lib(ctx)
    local asize = ir_node.retrieve_int_op(
        self:get_left_op(), ctx, 'int'
    )
    local idx = ir_node.retrieve_int_op(
        self:get_right_op(), ctx, 'int'
    )
    local data = ('(bvult ((_ extract 31 0) %s) ((_ extract 31 0) %s))')
        :format(idx, asize)
    return ctx.te_stack:store(self:get_ssa_reference(), data)
end

impls.IRNodeABCInt = {}
ir_node.extended(impls.IRNodeABCInt, IRNodeABCBase)

impls.IRNodeABCP32 = {}
ir_node.extended(impls.IRNodeABCP32, IRNodeABCBase)

impls.IRNodeABCU32 = {}
ir_node.extended(impls.IRNodeABCU32, IRNodeABCBase)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
