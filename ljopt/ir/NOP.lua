local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeNOP = {}
ir_node.extended(IRNodeNOP, ir_node.ir_node_base)

function IRNodeNOP:to_smt_lib()
    return ''
end

local function instance(_node_str)
    return IRNodeNOP
end

return {
    instance = instance
}
