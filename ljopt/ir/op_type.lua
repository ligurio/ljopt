--[[
Defines the set of operand types that can appear as
left_op / right_op on an IR node, together with
small constructor functions so the rest of the
code never has to interact with raw values manually.

Every operand is a table
{ type = <TYPE constant>, _value = <raw value> }.

TYPE constants
--------------
  ANY  - arbitrary type, used internally.
  BOOL - boolean constant.
  CARG - argument list to C function.
  FUN  - string description (fmtfunc output).
  I64  - int64 constant.
  IMM  - IRMlit, integer embedded to IR (#123).
  INT  - integer constant.
  LIT  - LuaJIT literals such as 'I', 'tab.hmask' etc.
  NUM  - Lua number.
  SSA  - positive integer (the SSA ref number).
  STR  - Lua string.
  TAB  - value is the table itself.
]]--

local OpType = {}

-- Type-tag constants.

OpType.ANY    = 'any'
OpType.BOOL   = 'bool'
OpType.CARG   = 'carg'
OpType.FUN    = 'function'
OpType.I64    = 'i64'
OpType.IMM    = 'imm'
OpType.INT    = 'int'
OpType.LIT    = 'lit'
OpType.NIL    = 'nil'
OpType.NUM    = 'num'
OpType.SSA    = 'ssa'
OpType.STR    = 'string'
OpType.TAB    = 'tab'

-- Operand metatable.

local op_mt = {}
op_mt.__index = op_mt

function op_mt:is_bool()   return self.type == OpType.BOOL end
function op_mt:is_carg()   return self.type == OpType.CARG end
function op_mt:is_fun()    return self.type == OpType.FUN  end
function op_mt:is_i64()    return self.type == OpType.I64  end
function op_mt:is_imm()    return self.type == OpType.IMM  end
function op_mt:is_int()    return self.type == OpType.INT  end
function op_mt:is_lit()    return self.type == OpType.LIT  end
function op_mt:is_num()    return self.type == OpType.NUM  end
function op_mt:is_ssa()    return self.type == OpType.SSA  end
function op_mt:is_str()    return self.type == OpType.STR  end
function op_mt:is_tab()    return self.type == OpType.TAB  end

function op_mt:get_bool()  assert(self:is_bool()); return self._value end
function op_mt:get_carg()  assert(self:is_carg()); return self._value end
function op_mt:get_fun()   assert(self:is_fun());  return self._value end
function op_mt:get_i64()   assert(self:is_i64());  return self._value end
function op_mt:get_imm()   assert(self:is_imm());  return self._value end
function op_mt:get_int()   assert(self:is_int());  return self._value end
function op_mt:get_lit()   assert(self:is_lit());  return self._value end
function op_mt:get_num()   assert(self:is_num());  return self._value end
function op_mt:get_ssa()   assert(self:is_ssa());  return self._value end
function op_mt:get_str()   assert(self:is_str());  return self._value end
function op_mt:get_tab()   assert(self:is_tab());  return self._value end

-- Returns a new operand object.
-- @type  one of the OpType constants above
-- @value the raw value appropriate for that type
function OpType.new(type, value)

    -- Map from `ir_dump` type strings to OpType.
    local supported_types = {
        bool         = OpType.BOOL,
        carg         = OpType.CARG,
        ["function"] = OpType.FUN,
        imm          = OpType.IMM,
        int          = OpType.INT,
        int64        = OpType.I64,
        lit          = OpType.LIT,
        number       = OpType.NUM,
        ssa          = OpType.SSA,
        string       = OpType.STR,
        table        = OpType.TAB,
    }
    assert(supported_types[type], 'Somehow this type is not exists: ' .. type)
    if type == 'carg' then
        local args = {}
        for i = 1, #value do
            args[i] = OpType.from_raw(value[i].tab, value[i].txt)
        end
        value = args
    end
    return setmetatable({ type = supported_types[type], _value = value }, op_mt)
end

-- Return the original string for an operand
-- as it would appear in an ir_dump trace line.
function OpType.to_string(op)
    -- Some instructions (such as NOP, LOOP, etc) have less than
    -- 2 arguments, so <nil> will be printed for their args.
    if op == nil then return '<nil>' end
    -- Prefer the stored display text when available.
    if op.txt ~= nil then return op.txt end
    -- Fallback: reconstruct from _value.
    return tostring(op._value)
end

-- Convert a raw { raw = <str>, type = <str>, value = <v> }
-- table produced by ljopt_formatsmt / ir_dump.lua
-- into the matching OpType object.
-- `txt` is the trimmed display string that ir_dump
-- printed for this operand (stored as op.txt so that
-- to_string() can return it verbatim). When `raw` is nil
-- but a non-empty `txt` is provided the operand is a
-- literal (mode flag, field name, etc.).
-- Returns nil when both arguments are nil / empty.
function OpType.from_raw(raw, txt)
    local op
    if raw ~= nil then
        local t = raw.type
        local v = raw.value
        if t == nil then
            -- Primitive constant (nil/false/true);
            -- fall through to txt.
            assert(txt ~= nil and txt ~= '')
            op = OpType.new(OpType.LIT, txt)
        else
            op = OpType.new(t, v)
        end
    end
    if op == nil and txt ~= nil and txt ~= '' then
        op = OpType.new(OpType.LIT, txt)
    end
    if op ~= nil and txt ~= nil and txt ~= '' then
        op.txt = txt
    end
    return op
end

return OpType
