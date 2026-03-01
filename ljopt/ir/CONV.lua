local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeCONV = {}
ir_node.extended(IRNodeCONV, ir_node.ir_node_base)

function IRNodeCONV:to_smt_lib(ctx)
    local left_op
    -- right_op is an OpKind.LIT whose value is the conversion descriptor
    -- string, e.g. "i64.num none".  Extract the plain string for parsing.
    local right_op_str = ir_node.OpKind.to_string(self:get_right_op())
    local data = ''

    local parsed_right_op = {}
    for i in string.gmatch(right_op_str, '%S+') do
        table.insert(parsed_right_op, i)
    end

    -- TODO: Support other conversions.
    if parsed_right_op[1] == 'num.int' then
        left_op = self:get_left_op()
        data = ir_node.retrieve_int_op(left_op, ctx, 'int')
        -- Convert int to floating point `num`.
        data = arith_utils.smt_int_to_fp(data)
    elseif parsed_right_op[1] == 'num.i64' then
        left_op = self:get_left_op()
        data = ir_node.retrieve_int_op(left_op, ctx, 'int')
        -- Convert int to floating point `num`.
        data = arith_utils.smt_i64_to_fp(data)
    elseif parsed_right_op[1] == 'int.num' then
        left_op = ir_node.retrieve_num_op(self:get_left_op(), ctx, 'num')
        -- TODO handle inputs that are out of range.
        -- LuaJIT follows C semantic when converting
        -- num -> int.
        -- And in C it's RTZ as stated in standard 6.3.1.4:
        -- luacheck: push no max_comment_line_length
        -- https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1256.pdf
        -- luacheck: pop
        data = string.format('((_ fp.to_sbv 64) RTZ %s)', left_op)
    elseif parsed_right_op[1] == 'i64.int' then
        data = ir_node.retrieve_int_op(
            self:get_left_op(), ctx, 'int'
        )
    elseif parsed_right_op[1] == 'i64.int sext' then
        data = ir_node.retrieve_int_op(
            self:get_left_op(), ctx, 'int'
        )
        data = arith_utils.smt_int_to_i64(data, true)
    elseif parsed_right_op[1] == 'i64.num' then
        left_op = ir_node.retrieve_num_op(
            self:get_left_op(), ctx, 'num'
        )
        -- TODO handle inputs that are out of range.
        data = arith_utils.smt_fp_to_i64(left_op)
    else
        assert(false, 'Unsupported type conversion: ' .. right_op_str)
    end

    local ssa_ref = self:get_ssa_reference()
    local te = ""
    if self:get_flags().irt_guard then
        -- Investigate when this guard can fail and how
        -- to verify it safely.
        te = ctx.te_stack:store(ssa_ref, 'true') .. '\n'
    end
    return te .. ctx.op_stack:store(
        ssa_ref, self:get_type(), data
    )
end

local function instance(_node_str)
    return IRNodeCONV
end

return {
    instance = instance
}
