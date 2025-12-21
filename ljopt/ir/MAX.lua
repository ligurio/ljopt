local bin_op = require('ljopt.ir.BinOp')
local ir_node = require('ljopt.ir.ir_node_base')

local impls = {}

impls.IRNodeMAXNum = {}
ir_node.extended(impls.IRNodeMAXNum, bin_op.BinOpNum)

impls.IRNodeMAXInt = {}
ir_node.extended(impls.IRNodeMAXInt, bin_op.BinOpInt)

function impls.IRNodeMAXInt:to_smt_lib(ctx)
    local left_op = self:retrieve_int_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_int_op(self:get_right_op(), ctx)
    local data = string.format('(ite (bvuge %s %s) %s %s)',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

impls.IRNodeMAXI64 = {}
ir_node.extended(impls.IRNodeMAXI64, bin_op.BinOpI64)

function impls.IRNodeMAXI64:to_smt_lib(ctx)
    local left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
    local right_op = self:retrieve_i64_op(self:get_right_op(), ctx)
    local data = string.format('(ite (bvuge %s %s) %s %s))',
        left_op, right_op, left_op, right_op
    )
    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end


local function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ['num'] = 'Num',
        ['i8'] = false,
        ['u8'] = false,
        ['i16'] = false,
        ['u16'] = false,
        ['int'] = 'Int',
        ['u32'] = false,
        ['i64'] = 'I64',
        ['u64'] = false,
        ['sfp'] = false,
    }
    local op_table = {
        ['num'] = 'fp.max',
        -- no SMTLIB bvmax version
        ['int'] = nil,
        ['i64'] = nil,
    }
    assert(type_table[type], 'Unsupported type for MAX operation', nil)
    local node = impls['IRNodeMAX' .. type_table[type]]:new(
        ssa_ref, flags, type, 'MAX', left_op, right_op
    )
    node.op_str = op_table[type]
    node.ignore_rounding = true
    return node
end

return {
    instance = instance
}
