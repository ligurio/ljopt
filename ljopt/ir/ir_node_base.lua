--[[
This class provides interface for all LuaJIT IR operations
translators.
]] --

local dev_checks = require('ljopt.dev_checks')
local arith_utils = require('ljopt.ir.arith_utils')
local utils = require('ljopt.utils')
local op_type = require('ljopt.ir.op_type')

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

-- Convert the bit pattern of a double stored
-- as #x<hex> to an int64 #x<hex>.
local function hex_double_to_i64_hex(hex_str)
    local clean_hex = hex_str:gsub("^#x", "")
    local hex_num = tonumber(clean_hex, 16)
    local converter = ffi.new("union { double d; uint64_t i; }")
    converter.i = hex_num
    local double_val = converter.d
    local int64_val = ffi.cast("int64_t", double_val)
    return string.format("#x%016x", tonumber(int64_val))
end

local function make_tab_ref(tab_id, idx)
    return ('(p32-val %s %s)'):format(tab_id, idx)
end

-- All retrieve_* functions below accept an
-- OpType object (or nil) as their first argument.

-- Returns the integer slot number for an SLOAD-style operand.
-- Accepts OpType.SSA (slot stored as integer value) or
-- OpType.LIT (text like '#2' – strips the leading '#').
local function retrieve_slot_op(op)
    assert(
        op ~= nil and op:is_imm(),
        'Op should be stack slot, got: ' .. op.type
    )
    return op:get_imm()
end

-- Loads a floating-point (num) value.
-- OpType.SSA - load from op_stack by SSA ref.
-- OpType.NUM - format as SMT floating-point bit-vector constant.
local function retrieve_num_op(op, ctx, type)
    if op == nil then
        utils.unreachable('retrieve_num_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op:get_ssa(), type)
    elseif op:is_num() then
        return string.format('((_ to_fp 11 53) %s)', op_type.to_string(op))
    elseif op:is_carg() then
        return retrieve_num_op(op:get_carg()[1])
    elseif op:is_bool() then
        utils.unreachable('Bool cannot be argument of num')
    end
    utils.unreachable(
        'retrieve_num_op: unsupported op type: ' .. tostring(op and op.type)
    )
end

-- Loads an integer (int / i32) value,
-- reinterpreting floats if needed.
-- OpType.SSA - load from op_stack as 'int'.
-- OpType.NUM - reinterpret the double bit-pattern as i64 hex.
local function retrieve_int_op(op, ctx, _type)
    if op == nil then
        utils.unreachable('retrieve_int_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op:get_ssa(), 'int')
    elseif op:is_num() then
        return hex_double_to_i64_hex(op_type.to_string(op))
    elseif op:is_bool() then
        utils.unreachable('Bool cannot be argument of int')
    end
    utils.unreachable(
        'retrieve_int_op: unsupported op type: ' .. tostring(op and op.type)
    )
end

-- Loads an unsigned 32-bit (u32) value.
-- Stored as a zero-extended 64-bit BV (canonical, high bits 0).
-- OpType.SSA - load from op_stack as 'u32'.
-- OpType.NUM - reinterpret the double bit-pattern as i64 hex
--   (positive u32 constants round-trip correctly).
local function retrieve_u32_op(op, ctx, _type)
    if op == nil then
        utils.unreachable('retrieve_u32_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op:get_ssa(), 'u32')
    elseif op:is_num() then
        return hex_double_to_i64_hex(op_type.to_string(op))
    elseif op:is_bool() then
        utils.unreachable('Bool cannot be argument of u32')
    end
    utils.unreachable(
        'retrieve_u32_op: unsupported op type: ' .. tostring(op and op.type)
    )
end

-- Loads a strings value,
-- reinterpreting floats if needed.
-- OpType.SSA - load from op_stack as 'str'.
-- OpType.STR - just return str.
local function retrieve_str_op(op, ctx)
    if op == nil then
        utils.unreachable('retrieve_str_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op:get_ssa(), op_type.STR)
    elseif op:is_str() then
        return arith_utils.const_str_to_smt_str(op:get_str())
    end
    utils.unreachable(
        'retrieve_str_op: unsupported op type: ' .. tostring(op and op.type)
    )
end

-- Loads a 64-bit integer (i64) value.
-- OpType.SSA - load from op_stack.
-- OpType.I64 - format the raw bit pattern as #x<16 hex digits>.
-- OpType.NUM - reinterpret double bit-pattern as i64.
local function retrieve_i64_op(op, ctx, type)
    if op == nil then
        utils.unreachable('retrieve_i64_op: op is nil')
    end
    if op:is_ssa() then
        return ctx.op_stack:load(op:get_ssa(), type)
    elseif op:is_i64() then
        return string.format('#x%016x', tonumber(op:get_i64()))
    elseif op:is_num() then
        return hex_double_to_i64_hex(op_type.to_string(op))
    elseif op:is_bool() then
        utils.unreachable('Bool cannot be argument of `i64`')
    end
    utils.unreachable(
        'retrieve_i64_op: unsupported op type: ' .. tostring(op and op.type)
    )
end

-- Tables are stored as first index in 3D memory array.
-- When reading table from op_stack we actually read a `pointer`
-- or index to 2D array (version and regular memory array).
local function retrieve_tab_op(operand, ctx, type)
    dev_checks('table', 'string', 'table')

    -- NOTE: Unused.
    -- Delayed until true dynamic tables are not supported.
    -- https://github.com/ligurio/ljopt/issues/46
    return ctx.op_stack:load(tonumber(operand), type)
end

-- All the other methods of `retrieve_*` are deprecated.
-- Usually we move value from something to the stack.
-- And for stacks more convenient to simply store MemCell.
local function retrieve_raw_val(op, ctx)
    if op:is_ssa() then
        return ctx.op_stack:load(op:get_ssa(), op_type.ANY)
    elseif op:is_str() then
        return arith_utils.const_str_to_memcell(op:get_str())
    elseif op:is_num() then
        return arith_utils.const_num_to_memcell(op:get_num())
    elseif op:is_bool() then
        return arith_utils.const_num_to_memcell(op:get_bool())
    else
        utils.unreachable(op.type)
    end
end

local function retrieve_tab_id(op, ctx)
    return ('(get-p32-tab %s)'):format(retrieve_raw_val(op, ctx))
end

local function retrieve_tab_ptr(op, ctx)
    return ('(get-p32-idx %s)'):format(retrieve_raw_val(op, ctx))
end

-- Loads versioned table memory + cell index for a hash/array
-- left operand. Returns the table id, the cell index and the
-- raw memcell expression `(select <versioned-tab-mem> <idx>)`.
local function retrieve_tab_ref(op, ctx)
    local tab_id = retrieve_tab_id(op, ctx)
    local tab_ptr = retrieve_tab_ptr(op, ctx)
    local raw_cell = ('(select %s %s)'):format(
        ctx.mem_stack:load(tab_id), tab_ptr
    )
    return tab_id, tab_ptr, raw_cell
end

-- Decode a memory cell as a table id. A cell holding no table --
-- a metatable field still nil, an array slot that never got one
-- -- gets an id derived from the cell itself, so both passes
-- agree on it by congruence.
local function get_table_uid(raw_cell)
    return ('(ite ((_ is tab-val) %s) (get-tab %s)'
        .. ' (tab_uid %s))'):format(
        raw_cell, raw_cell, raw_cell
    )
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
    make_tab_ref = make_tab_ref,
    retrieve_slot_op = retrieve_slot_op,
    retrieve_tab_op = retrieve_tab_op,
    retrieve_raw_val = retrieve_raw_val,
    retrieve_tab_id = retrieve_tab_id,
    retrieve_tab_ptr = retrieve_tab_ptr,
    retrieve_tab_ref = retrieve_tab_ref,
    get_table_uid = get_table_uid,
    retrieve_num_op = retrieve_num_op,
    retrieve_str_op = retrieve_str_op,
    retrieve_int_op = retrieve_int_op,
    retrieve_i64_op = retrieve_i64_op,
    retrieve_u32_op = retrieve_u32_op,
}
