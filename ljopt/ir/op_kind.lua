--[[
Defines the set of operand kinds that can appear as left_op / right_op on an
IR node, together with small constructor functions so the rest of the code
never has to build raw tables by hand.

Every operand is a table  { kind = <KIND constant>, value = <raw value> }.

KIND constants
--------------
  SSA    – SSA reference: value is a positive integer (the SSA ref number).
  NUM    – floating-point constant: value is a Lua number.
  STR    – string constant: value is a Lua string.
  FUN    – function constant: value is a string description (fmtfunc output).
  TAB    – table constant: value is the formatted table string from ljopt_formatsmt.
  INT64  – int64 constant: value is a Lua number (the raw int64 bit pattern).
  LIT    – literal / mode operand: value is a string such as "I", "tab.hmask",
           "i64.num none", "#2", etc.  Used wherever LuaJIT encodes the operand
           as an IRMlit field rather than a proper SSA ref or constant.
  BOOL   – boolean constant: value is true or false.
]]--

local OpKind = {}

-- ── Type-tag constants ───────────────────────────────────────────────────────

OpKind.SSA    = "ssa"
OpKind.S_SLOT = "s_slot"
OpKind.NUM    = "number"
OpKind.STR    = "string"
OpKind.FUN    = "function"
OpKind.TAB    = "table"
OpKind.INT64  = "int64"
OpKind.LIT    = "lit"
OpKind.BOOL   = "bool"

-- ── Operand metatable (allows method-call syntax: op:is_ssa(), etc.) ────────

local op_mt = {}
op_mt.__index = op_mt

function op_mt:is_ssa()    return self.kind == OpKind.SSA    end
function op_mt:is_slt()    return self.kind == OpKind.S_SLOT end
function op_mt:is_num()    return self.kind == OpKind.NUM    end
function op_mt:is_str()    return self.kind == OpKind.STR    end
function op_mt:is_fun()    return self.kind == OpKind.FUN    end
function op_mt:is_tab()    return self.kind == OpKind.TAB    end
function op_mt:is_i64()  return self.kind == OpKind.INT64  end
function op_mt:is_lit()    return self.kind == OpKind.LIT    end
function op_mt:is_bool()   return self.kind == OpKind.BOOL   end

-- ── Generic constructor ──────────────────────────────────────────────────────

-- Returns a new operand object.
-- @kind  one of the OpKind constants above
-- @value the raw value appropriate for that kind
function OpKind.new(kind, value)
    return setmetatable({ kind = kind, value = value }, op_mt)
end

-- ── Per-kind convenience constructors ────────────────────────────────────────

-- SSA reference. n must be a positive integer.
function OpKind.ssa(n)
    return OpKind.new(OpKind.SSA, n)
end

-- S_SLOT reference. n must be a positive integer.
function OpKind.s_slot(n)
    return OpKind.new(OpKind.S_SLOT, n)
end

-- Floating-point number constant. n is a Lua number.
function OpKind.num(n)
    return OpKind.new(OpKind.NUM, n)
end

-- String constant. s is a Lua string.
function OpKind.str(s)
    return OpKind.new(OpKind.STR, s)
end

-- Function constant. desc is a string (fmtfunc / ffname output).
function OpKind.fun(desc)
    return OpKind.new(OpKind.FUN, desc)
end

-- Table constant. desc is the formatted table string.
function OpKind.tab(desc)
    return OpKind.new(OpKind.TAB, desc)
end

-- int64 constant. n is a Lua number holding the raw bit pattern.
function OpKind.int64(n)
    return OpKind.new(OpKind.INT64, n)
end

-- Literal / mode operand. s is the raw text string (e.g. "I", "tab.hmask").
function OpKind.lit(s)
    return OpKind.new(OpKind.LIT, s)
end

-- Boolean constant.
function OpKind.bool(b)
    return OpKind.new(OpKind.BOOL, b)
end


-- ── String representation ─────────────────────────────────────────────────────

-- Return the original display string for an operand as it would appear in
-- an ir_dump trace line.  For objects created via from_raw() this is exactly
-- the trimmed text that ir_dump printed; for objects created directly via the
-- per-kind constructors it falls back to a formatted representation of value.
function OpKind.to_string(op)
    if op == nil then return '<nil>' end
    -- Prefer the stored display text when available.
    if op.txt ~= nil then return op.txt end
    -- Fallback: reconstruct from value.
    local k = op.kind
    if     k == OpKind.SSA   then return string.format('%04d', op.value)
    elseif k == OpKind.LIT   then return tostring(op.value)
    else   return tostring(op.value)
    end
end

-- ── Conversion from raw irins tables ─────────────────────────────────────────

-- Convert a raw  { type = <str>, value = <v> }  table produced by
-- ljopt_formatsmt / ir_dump.lua into the matching OpKind object.
-- `txt` is the trimmed display string that ir_dump printed for this operand
-- (stored as op.txt so that to_string() can return it verbatim).
-- When `raw` is nil but a non-empty `txt` is provided the operand is a
-- literal (mode flag, field name, etc.).
-- Returns nil when both arguments are nil / empty.
function OpKind.from_raw(raw, txt)
    local op
    if raw ~= nil then
        local t = raw.type
        local v = raw.value
        if     t == nil           then -- primitive constant (nil/false/true); fall through to txt
        elseif t == OpKind.SSA    then op = OpKind.ssa(v)
        elseif t == OpKind.S_SLOT then op = OpKind.s_slot(v)
        elseif t == OpKind.NUM    then op = OpKind.num(v)
        elseif t == OpKind.STR    then op = OpKind.str(v)
        elseif t == OpKind.FUN    then op = OpKind.fun(v)
        elseif t == OpKind.TAB    then op = OpKind.tab(v)
        elseif t == OpKind.INT64  then op = OpKind.int64(v)
        else
            error('OpKind.from_raw: unknown type ' .. tostring(t))
        end
    end
    if op == nil and txt ~= nil and txt ~= '' then
        op = OpKind.lit(txt)
    end
    if op ~= nil and txt ~= nil and txt ~= '' then
        op.txt = txt   -- cache original display text for to_string()
    end
    return op
end

return OpKind
