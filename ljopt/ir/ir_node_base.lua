--[[
    This class provides interface for all LuaJIT IR operations translators.
]] --

local dev_checks = require('ljopt.dev_checks')

local function get_ssa_reference(self)
    dev_checks('table')

    return self._ssa_ref
end

local function get_flags(self)
    dev_checks('table')

    return self._flags
end

local function get_type(self)
    dev_checks('table')

    return self._type
end

local function get_opcode(self)
    dev_checks('table')

    return self._opcode
end

local function get_left_op(self)
    dev_checks('table')

    return self._left_op
end

local function get_right_op(self)
    dev_checks('table')

    return self._right_op
end

local function parse_op(self, operand, maxrecord)
    dev_checks('table', 'string', '?number')

    -- Maximum number of recorded IR instructions in LuaJIT.
    local JIT_P_maxrecord = 4000
    maxrecord = maxrecord or JIT_P_maxrecord

    -- TODO support for other types
    -- TODO inf?
    -- TODO other modifiers
    if operand:sub(1, 1) == '+' or operand:sub(1, 1) == '-' or
        operand:sub(-1, -1) == 'L' or operand == 'NaN' then
        -- TODO support for arith other types
        assert(self:get_type() == 'num' or self:get_type() == 'int' or
            self:get_type() == 'i64' or self:get_type() == 'u64')
        return self:get_type()
    elseif string.len(operand) == string.len(tostring(maxrecord)) then
        return 'op'
    end
end

local function retrieve_slot_op(self, operand)
    dev_checks('table', 'string')

    return tonumber(operand:sub(2))
end

local function retrieve_num_op(self, operand, ctx)
    dev_checks('table', 'string', 'table')

    local op_type = self:parse_op(operand)
    if op_type == 'op' then
        operand = ctx.op_stack:load(tonumber(operand), self:get_type())
    elseif op_type == 'num' then
        -- TODO rewrite
        local conv = '((_ to_fp 11 53) roundNearestTiesToEven %s)'
        operand = operand:gsub('e', ' '):gsub('+', '')
        operand = string.format(conv, operand)
    end
    return operand
end

local function retrieve_int_op(self, operand, ctx)
    dev_checks('table', 'string', 'table')

    local op_type = self:parse_op(operand)
    if op_type == 'op' then
        operand = ctx.op_stack:load(tonumber(operand), self:get_type())
    elseif op_type == 'int' then
        local conv = string.format('#x%.16x', operand)
        operand = string.format(conv, operand)
    end
    return operand
end

local function retrieve_i64_op(self, operand, ctx)
    dev_checks('table', 'string', 'table')

    local op_type = self:parse_op(operand)
    if op_type == 'op' then
        operand = ctx.op_stack:load(tonumber(operand), self:get_type())
    elseif op_type == 'i64' then
        if operand:sub(-1, -1) == 'L' then
            operand = operand:sub(1, -2)
        end
        if operand:sub(-1, -1) == 'L' then
            operand = operand:sub(1, -2)
        end
        local conv = string.format('#x%.32x', operand)
        operand = string.format(conv, operand)
    end
    return operand
end

local ir_node_base = {}
function ir_node_base:new(ssa_ref, flags, type, opcode, left_op, right_op)
    dev_checks('table', 'string', 'string', '?string', 'string', '?string', '?string')

    self._ssa_ref = tonumber(ssa_ref)
    self._flags = flags
    self._type = type
    self._opcode = opcode
    self._left_op = left_op
    self._right_op = right_op

    local public = {
        get_ssa_reference = get_ssa_reference,
        get_flags = get_flags,
        get_type = get_type,
        get_opcode = get_opcode,
        get_left_op = get_left_op,
        get_right_op = get_right_op,
        parse_op = parse_op,
        retrieve_slot_op = retrieve_slot_op,
        retrieve_num_op = retrieve_num_op,
        retrieve_int_op = retrieve_int_op,
        retrieve_i64_op = retrieve_i64_op
    }

    -- This method should be overridden in child classes.
    function ir_node_base.to_smt_lib()
        return assert(false, 'Unimplemented')
    end

    setmetatable(public, self)
    self.__index = self;
    return public
end

local function extended(child, parent)
    dev_checks('table', 'table')
    setmetatable(child, { __index = parent })
end

return {
    ir_node_base = ir_node_base,
    extended = extended
}
