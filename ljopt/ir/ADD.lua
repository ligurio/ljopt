local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeADDNum = {
    op_str = 'fp.add',
    const_fn = function(a, b) return a + b end
}
ir_node.extended(impls.IRNodeADDNum, bin_op.BinOpNum)

impls.IRNodeADDInt = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDInt, bin_op.BinOpInt)

impls.IRNodeADDI64 = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDI64, bin_op.BinOpI64)

impls.IRNodeADDU32 = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDU32, bin_op.BinOpU32)

impls.IRNodeADDP64 = { op_str = 'bvadd' }
ir_node.extended(impls.IRNodeADDP64, bin_op.BinOpI64)

-- Pointer arithmetic on a string constant (the address of a GC
-- string's char data in ffi.copy/ffi.fill) cannot be modelled, as
-- string literals are not part of the byte-addressed FFI memory.
-- Drop the node and its copy chain as NYI.
function impls.IRNodeADDP64.is_implemented(_flags, _type, _opcode,
                                            left_op, right_op)
    if left_op:is_str() or right_op:is_str() then
        return false
    end
    return true
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
