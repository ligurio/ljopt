-- A call to a helper that takes the lua_State: math.random's
-- step, string interning, table allocation and the like.
--
-- What the helper computes is not modelled. The result is an
-- uninterpreted value keyed by which helper was called, so both
-- traces get the same one and equivalent calls match by
-- congruence -- the same bargain CALLXS makes for external C
-- calls. The state such a helper advances is not modelled
-- either, so two calls to one helper look equal here; a trace
-- that dropped or reordered such a call is not detected.
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')

local impls = {}

local fns = {[op_type.NUM] = 'calls_num', [op_type.INT] = 'calls_int'}

-- A stable number for the callee name: both recordings spell it
-- the same, so both reach the same uninterpreted value.
local function callee_id(name)
    local h = 5381
    for i = 1, #name do
        h = (h * 33 + name:byte(i)) % 2147483647
    end
    return h
end

local function make(smt_type)
    local node = {}
    ir_node.extended(node, ir_node.ir_node_base)
    function node:to_smt_lib(ctx)
        local ssa_ref = self:get_ssa_reference()
        local name = op_type.to_string(self:get_right_op())
        return ('%s\n%s'):format(
            ctx.te_stack:store(ssa_ref, 'true'),
            ctx.op_stack:store(ssa_ref, smt_type,
                ('(%s %d)'):format(fns[smt_type], callee_id(name)))
        )
    end
    function node.is_implemented(_flags, _type, _opcode, _left_op, right_op)
        return right_op ~= nil and op_type.to_string(right_op) ~= '<nil>'
    end
    return node
end

impls.IRNodeCALLSNum = make(op_type.NUM)
impls.IRNodeCALLSInt = make(op_type.INT)

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
