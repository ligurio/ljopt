--[[
This class provides interface for all LuaJIT IR operations
translators.
]] --

local dev_checks = require('ljopt.dev_checks')
local utils = require('ljopt.utils')
local OpKind = require('ljopt.ir.op_kind')

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

local ffi = require("ffi")

-- Convert the bit pattern of a double stored as #x<hex> to an int64 #x<hex>.
local function hex_double_to_i64_hex(hex_str)
    local clean_hex = hex_str:gsub("^#x", "")
    local hex_num = tonumber(clean_hex, 16)
    local converter = ffi.new("union { double d; uint64_t i; }")
    converter.i = hex_num
    local double_val = converter.d
    local int64_val = ffi.cast("int64_t", double_val)
    return string.format("#x%016x", tonumber(int64_val))
end

-- All retrieve_* functions below accept an OpKind object (or nil) as their
-- first argument.  They replace the old string-based API.

-- Returns the integer slot number for an SLOAD-style operand.
-- Accepts OpKind.SSA (slot stored as integer value) or
-- OpKind.LIT (text like "#2" – strips the leading '#').
local function retrieve_slot_op(op)
    assert(op ~= nil and op:is_slt(), "Op should be stack slot, got: " .. op.kind)
    -- Literal slot encoded as "#2", "#10", …
    return op.value
end

-- Loads a floating-point (num) value.
-- OpKind.SSA  → load from op_stack by SSA ref.
-- OpKind.NUM  → format as SMT floating-point bit-vector constant.
local function retrieve_num_op(op, ctx, type)
    if op == nil then
        utils.unreachable('retrieve_num_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op.value, type)
    elseif op:is_num() then
        return string.format('((_ to_fp 11 53) %s)', OpKind.to_string(op))
    end
    utils.unreachable('retrieve_num_op: unsupported op kind: ' .. tostring(op and op.kind))
end

-- Loads an integer (int / i32) value, reinterpreting floats if needed.
-- OpKind.SSA   → load from op_stack as 'int'.
-- OpKind.NUM   → reinterpret the double bit-pattern as i64 hex.
local function retrieve_int_op(op, ctx, _type)
    if op == nil then
        utils.unreachable('retrieve_int_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op.value, 'int')
    elseif op:is_num() then
        return hex_double_to_i64_hex(OpKind.to_string(op))
    end
    utils.unreachable('retrieve_int_op: unsupported op kind: ' .. tostring(op and op.kind))
end

-- Loads a 64-bit integer (i64) value.
-- OpKind.SSA   → load from op_stack.
-- OpKind.INT64 → format the raw bit pattern as #x<16 hex digits>.
-- OpKind.NUM   → reinterpret double bit-pattern as i64.
local function retrieve_i64_op(op, ctx, type)
    if op == nil then
        utils.unreachable('retrieve_i64_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op.value, type)
    elseif op:is_i64() then
        return string.format("#x%016x", tonumber(op.value))
    elseif op:is_num() then
        return hex_double_to_i64_hex(OpKind.to_string(op))
    end
    utils.unreachable('retrieve_i64_op: unsupported op kind: ' .. tostring(op and op.kind))
end

local function retrieve_p64_op(op, ctx, type)
    if op == nil then
        utils.unreachable('retrieve_p64_op: op is nil')
    end
    assert(op:is_ssa(), op.kind)
    if op:is_ssa() then
        return ctx.op_stack:load(op.value, type)
    elseif op:is_i64() then
        return string.format("#x%016x", tonumber(op.value))
    elseif op:is_num() then
        return hex_double_to_i64_hex(OpKind.to_string(op))
    end
    utils.unreachable('retrieve_i64_op: unsupported op kind: ' .. tostring(op and op.kind))
end

-- Tables are stored as the first index in the 3-D memory array.
-- Accepts OpKind.SSA only (tables are always referenced via SSA).
local function retrieve_tab_op(op, ctx, type)
    if op == nil then
        utils.unreachable('retrieve_tab_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op.value, type)
    end
    utils.unreachable('retrieve_tab_op: unsupported op kind: ' .. tostring(op and op.kind))
end

local ir_node_base = {}
function ir_node_base:new(ssa_ref, flags, type, opcode, left_op, right_op)
    dev_checks(
        'table', 'string', 'table', '?string', 'string', '?table', '?table'
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

-- Child nodes can override it, by default assume all nodes
-- are implemented. If node is not implemented it means we'll
-- skip this IR and all its' dependencies.
function ir_node_base:is_implemented(_flags, _type, _opcode,
                                     _left_op, _right_op)
    return true
end

local function extended(child, parent)
    dev_checks('table', 'table')
    setmetatable(child, { __index = parent })
end

return {
    ir_node_base = ir_node_base,
    extended = extended,
    retrieve_slot_op = retrieve_slot_op,
    retrieve_tab_op = retrieve_tab_op,
    retrieve_num_op = retrieve_num_op,
    retrieve_int_op = retrieve_int_op,
    retrieve_i64_op = retrieve_i64_op,
    retrieve_p64_op = retrieve_p64_op,
    OpKind = OpKind,
}
