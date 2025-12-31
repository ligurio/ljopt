local ir_node = require('ljopt.ir.ir_node_base')

local IRNodeCONV = {}
ir_node.extended(IRNodeCONV, ir_node.ir_node_base)

function IRNodeCONV:to_smt_lib(ctx)
    local left_op
    local right_op = self:get_right_op()
    local data = ''

    local parsed_right_op = {}
    for i in string.gmatch(right_op, '%S+') do
        table.insert(parsed_right_op, i);
     end

    -- TODO: Support other conversions.
    if parsed_right_op[1] == 'num.int' then
        left_op = self:get_left_op()
        data = self:retrieve_int_op(left_op, ctx)
        -- We optimize useless conversion fp -> int -> fp
        -- in case of num.
        -- Make actual conversion only if it's not 'num'.
        if self:parse_op(left_op) ~= 'num' then
            -- LuaJIT follows C semantic when converting
            -- num -> int.
            -- And in C it's RTZ as stated in standard 6.3.1.4:
            -- luacheck: push no max_comment_line_length
            -- https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1256.pdf
            -- luacheck: pop
            data = string.format('RTZ (bv2int %s)', data)
        end
        data = string.format('((_ to_fp 11 53) %s)', data)
    elseif parsed_right_op[1] == 'int.num' then
        left_op = self:retrieve_num_op(self:get_left_op(), ctx)
        -- TODO handle inputs that are out of range.
        data = string.format('((_ fp.to_sbv 32) %s)', left_op)
    elseif parsed_right_op[1] == 'num.i64' then
        left_op = self:retrieve_i64_op(self:get_left_op(), ctx)
        -- TODO recheck rounding behaviour.
        data = string.format('((_ to_fp 11 53) %s)', left_op)
    elseif parsed_right_op[1] == 'i64.num' then
        left_op = self:retrieve_num_op(self:get_left_op(), ctx)
        -- TODO handle inputs that are out of range.
        data = string.format('((_ fp.to_sbv 64) RNE %s)', left_op)
    else
        assert(false, 'Unsupported type conversion: '..right_op)
    end

    return ctx.op_stack:store(self:get_ssa_reference(), self:get_type(), data)
end

local function instance(ssa_ref, flags, node_str, type, left_op, right_op)
    return IRNodeCONV:new(ssa_ref, flags, type, 'CONV', left_op, right_op)
end

return {
    instance = instance
}
