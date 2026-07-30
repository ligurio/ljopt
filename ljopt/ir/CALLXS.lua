local ir_node = require('ljopt.ir.ir_node_base')
local utils = require('ljopt.utils')

local impls = {}

local function gather_args(left_op)
    if left_op == nil then
        return {}
    end
    if left_op:is_carg() then
        return left_op:get_carg()
    end
    -- Single non-CARG argument (rare): treat as one-element list.
    return {left_op}
end

local IRNodeCALLXSBase = {}
ir_node.extended(IRNodeCALLXSBase, ir_node.ir_node_base)

-- Only callxs_1..4 are declared, so a call with any other arity
-- is not implemented: mark it NYI and let the node (with its
-- dependencies) be skipped instead of failing the whole trace.
function IRNodeCALLXSBase.is_implemented(_flags, _type, _opcode,
                                        left_op, _right_op)
    local arity = #gather_args(left_op)
    if arity < 1 or arity > 4 then
        utils.debug_msg(('CALLXS: arity %d not supported'):format(arity))
        return false
    end
    return true
end

-- External C calls are modelled by an uninterpreted
-- callxs_<arity> over the i64 argument bitvectors, so equivalent
-- traces match by congruence. Result is stored as `self.type`.
function IRNodeCALLXSBase:to_smt_lib(ctx)
    local args = gather_args(self:get_left_op())
    local arity = #args
    if arity < 1 or arity > 4 then
        utils.unreachable(
            'It should have been marked as NYI: CALLXS arity ' ..
            tostring(arity)
        )
    end
    local arg_bvs = {}
    for i, a in ipairs(args) do
        arg_bvs[i] = ir_node.retrieve_i64_op(a, ctx, 'i64')
    end
    local result = ('(%s%d %s)'):format(
        self.fn_prefix, arity, table.concat(arg_bvs, ' ')
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self.type, result)
end

impls.IRNodeCALLXSInt = { type = 'int', fn_prefix = 'callxs_' }
ir_node.extended(impls.IRNodeCALLXSInt, IRNodeCALLXSBase)

impls.IRNodeCALLXSI64 = { type = 'i64', fn_prefix = 'callxs_' }
ir_node.extended(impls.IRNodeCALLXSI64, IRNodeCALLXSBase)

-- A double-returning C function, e.g. FFI `double sin(double)`.
-- callxs_fp_<arity> returns an fp, so the result lands in the
-- MemCell's fp-val directly instead of being reinterpreted from
-- bits. Congruence still ties the two traces together: the same
-- callee pointer and arguments give the same double.
impls.IRNodeCALLXSNum = { type = 'num', fn_prefix = 'callxs_fp_' }
ir_node.extended(impls.IRNodeCALLXSNum, IRNodeCALLXSBase)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance,
}
