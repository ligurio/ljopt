--[[
This class provides interface for all LuaJIT IR operations
translators.
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

local function parse_op(operand, maxrecord)
    dev_checks('table', 'string', '?number')

    -- Maximum number of recorded IR instructions in LuaJIT.
    local JIT_P_maxrecord = 4000
    maxrecord = maxrecord or JIT_P_maxrecord

    -- TODO: Add integer OPs, right now we support only floats,
    -- represented as #x0123456.
    if operand:sub(1, 2) == '#x' then
        -- We represent as a constant only numbers.
        -- They should
        return 'num'
    elseif operand == 'false' or operand == 'true' then
        assert('Unreachable?')
        return 'bool'
    elseif string.len(operand) == string.len(tostring(maxrecord)) then
        return 'op'
    end
    assert('Unknown type')
    return self:get_type()
end

local function retrieve_slot_op(operand)
    dev_checks('table', 'string')

    return tonumber(operand:sub(2))
end

-- Loads number from stack.
-- 
local function retrieve_num_op(operand, ctx, type)
    dev_checks('table', 'string', 'table')

    local op_type = parse_op(operand)
    if op_type == 'op' then
        operand = ctx.op_stack:load(tonumber(operand), type)
    elseif op_type == 'num' then
        local conv = '((_ to_fp 11 53) %s)'
        operand = string.format(conv, operand)
    end
    return operand
end

local ffi = require("ffi")
local function hex_double_to_i64_hex(hex_str)
    -- Remove #x prefix if present
    local clean_hex = hex_str:gsub("^#x", "")

    -- Convert hex string to number
    local hex_num = tonumber(clean_hex, 16)

    -- Use FFI to interpret the bits as double
    local converter = ffi.new("union { double d; uint64_t i; }")
    converter.i = hex_num  -- Set the bit pattern

    -- Get the actual double value
    local double_val = converter.d

    -- Convert to int64 and format as hex
    local int64_val = ffi.cast("int64_t", double_val)
    return string.format("#x%016x", tonumber(int64_val))
end


local function retrieve_int_op(operand, ctx, type)
    dev_checks('table', 'string', 'table')

    local op_type = parse_op(operand)
    if op_type == 'op' then
        -- Result of self may be num, but operand
        -- should be loaded as int.
        return ctx.op_stack:load(tonumber(operand), 'int')
    elseif op_type == 'int' then
        if string.sub(operand, 1, 2) == '#x' then
            -- Kinda optimization, lets convert inplace.
            -- Otherwise bv(float) -> int -> bv(int).
            return hex_double_to_i64_hex(operand)
        else
            -- Unreachable?
            assert(false)
        end
    elseif op_type == 'num' then
        if string.sub(operand, 1, 2) == '#x' then
            return hex_double_to_i64_hex(operand)
        else
            -- Unreachable?
            assert(false)
        end
    end
    assert(false, 'op_type ' .. op_type .. ' is not supported yet')
end

local function retrieve_i64_op(self, operand, ctx)
    dev_checks('table', 'string', 'table')

    local op_type = parse_op(operand)
    if op_type == 'op' then
        operand = ctx.op_stack:load(tonumber(operand), self:get_type())
    elseif op_type == 'i64' then
        if operand:sub(-1, -1) == 'L' then
            operand = operand:sub(1, -2)
        end
        if operand:sub(-1, -1) == 'L' then
            operand = operand:sub(1, -2)
        end
        local conv = string.format('#x%.16x', operand)
        operand = string.format(conv, operand)
    end
    return operand
end

local ir_node_base = {}
function ir_node_base:new(ssa_ref, flags, type, opcode, left_op, right_op)
    dev_checks(
        'table', 'string', 'string', '?string', 'string', '?string', '?string'
    )

    local public = {
        _ssa_ref = tonumber(ssa_ref),
        _flags = flags,
        _type = type,
        _opcode = opcode,
        _left_op = left_op,
        _right_op = right_op,

        get_ssa_reference = get_ssa_reference,
        get_flags = get_flags,
        get_type = get_type,
        get_opcode = get_opcode,
        get_left_op = get_left_op,
        get_right_op = get_right_op,
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
    extended = extended,
    retrieve_slot_op = retrieve_slot_op,
    retrieve_num_op = retrieve_num_op,
    retrieve_int_op = retrieve_int_op,
    retrieve_i64_op = retrieve_i64_op,
    parse_op = parse_op,
}
