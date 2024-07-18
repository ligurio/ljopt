--[[
Provides an instance of an IR node that represents a dummy
operation. It's used to skip IR nodes that are not yet supported
by the ljopt.
]]

local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeDummy = {}
ir_node.extended(IRNodeDummy, ir_node.ir_node_base)

function IRNodeDummy:to_smt_lib()
    return ''
end

local function instance(ssa_ref, flags, type, left_op, right_op)
    return IRNodeDummy:new(ssa_ref, flags, type, 'dummy', left_op, right_op)
end

local is_dummy_node = true

return {
    instance = instance,
    is_dummy_node = is_dummy_node
}
