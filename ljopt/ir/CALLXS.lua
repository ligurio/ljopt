local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
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

-- An operand as a whole MemCell. The cell carries its own type
-- tag, so the argument goes to the uninterpreted function without
-- passing through an ADT accessor. That matters because the two
-- traces do not always box a value the same way -- one may pass a
-- literal where the other passes the result of a num CONV -- and
-- `get-bv` on an fp-val cell is unconstrained, which would make
-- an identical call look divergent.
local function retrieve_cell(op, ctx)
    if op:is_ssa() then
        return ctx.op_stack:load(op:get_ssa(), op_type.ANY)
    elseif op:is_num() then
        return arith_utils.const_num_to_memcell(op:get_num())
    elseif op:is_i64() then
        return arith_utils.const_i64_to_memcell(op:get_i64())
    end
    utils.unreachable('CALLXS: unsupported operand ' .. tostring(op.type))
end

local IRNodeCALLXSBase = {}
ir_node.extended(IRNodeCALLXSBase, ir_node.ir_node_base)

-- The callee counts as an operand, so a call with N arguments
-- needs callxs_<N+1>. Only 1..5 are declared, and a call whose
-- callee the recorder did not hand over cannot be modelled at
-- all: mark those NYI and let the node (with its dependencies)
-- be skipped instead of failing the whole trace.
function IRNodeCALLXSBase.is_implemented(_flags, _type, _opcode,
                                        left_op, right_op)
    if right_op == nil then
        utils.debug_msg('CALLXS: no callee')
        return false
    end
    local arity = #gather_args(left_op) + 1
    if arity > 5 then
        utils.debug_msg(('CALLXS: arity %d not supported'):format(arity))
        return false
    end
    return true
end

-- External C calls are modelled by an uninterpreted
-- callxs_<arity> over the callee and the argument cells, so
-- equivalent traces match by congruence. Result is stored as
-- `self.type`.
--
-- The callee has to be an argument of the uninterpreted function
-- rather than baked into its name: it is often not a constant
-- (an FFI function pointer loaded out of an array, say), and two
-- traces that call different pointers with the same arguments are
-- exactly the divergence this check exists to find.
function IRNodeCALLXSBase:to_smt_lib(ctx)
    local args = gather_args(self:get_left_op())
    local arity = #args + 1
    if arity > 5 then
        utils.unreachable(
            'It should have been marked as NYI: CALLXS arity ' ..
            tostring(arity)
        )
    end
    local cells = { retrieve_cell(self:get_right_op(), ctx) }
    for i, a in ipairs(args) do
        cells[i + 1] = retrieve_cell(a, ctx)
    end
    local result = ('(%s%d %s)'):format(
        self.fn_prefix, arity, table.concat(cells, ' ')
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
