local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodePOWNum = {}
ir_node.extended(impls.IRNodePOWNum, bin_op.BinOpNum)

impls.IRNodePOWInt = {}
ir_node.extended(impls.IRNodePOWInt, bin_op.BinOpInt)

impls.IRNodePOWI64 = {}
ir_node.extended(impls.IRNodePOWI64, bin_op.BinOpI64)

local function instance()
    assert(false, "UNSUPPORTED!")
    return nil
end

return {
    instance = instance
}
