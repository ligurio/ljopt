-- Decode a jit.util.irfuzz() pass buffer into the trace_record
-- shape that ljopt.ir_smtlib.translate() consumes.
--
-- The harness returns each replayed IR buffer as flat numeric
-- arrays (m, ot, op1, op2 per instruction; kot/kval for the
-- constant section; map for generator-ref -> ref). This module
-- reconstructs the node table that ir_dump.lua would have
-- produced, so the rest of ljopt is oblivious to the trace's
-- synthetic origin.
--
-- The operand decode mirrors ljopt/ir_dump.lua:dump_ir (the
-- non-CALL, non-CNEW-special path), reusing float_to_smt_bv for
-- numeric constants so encodings stay byte-identical with the
-- recorded path.

local ffi = require("ffi")
local bit = require("bit")
local band, shr = bit.band, bit.rshift
local vmdef = require("jit.vmdef")

-- Double -> SMT bitvector literal. A self-contained copy of the
-- same one-liner ir_dump_utils and tests/ir_tests.lua use;
-- kept local so the fuzzer does not reach into ljopt internals
-- to format operands.
local function float_to_smt_bv(x)
  local u = ffi.new("union { double d; uint64_t i; }")
  u.d = x
  return ("#x%s"):format(bit.tohex(u.i, 16))
end

-- IRT byte -> short type string (ORDER LJ_T, same as
-- ir_dump.lua).
local irtype_text = {
  [0] = "nil", "fal", "tru", "lud", "str", "p32", "thr", "pro", "fun",
  "p64", "cdt", "tab", "udt", "flt", "num", "i8", "u8", "i16", "u16",
  "int", "u32", "i64", "u64", "sfp",
}

-- Literal-operand name tables (op2 == IRMlit). Mirrors
-- ir_dump.lua's litname; kept self-contained so requiring this
-- module has no jit attach side effects.
local litname = {
  ["SLOAD "] = setmetatable({}, { __index = function(t, mode)
    local s = ""
    if band(mode, 1) ~= 0 then s = s .. "P" end
    if band(mode, 2) ~= 0 then s = s .. "F" end
    if band(mode, 4) ~= 0 then s = s .. "T" end
    if band(mode, 8) ~= 0 then s = s .. "C" end
    if band(mode, 16) ~= 0 then s = s .. "R" end
    if band(mode, 32) ~= 0 then s = s .. "I" end
    if band(mode, 64) ~= 0 then s = s .. "K" end
    t[mode] = s
    return s
  end }),
  ["XLOAD "] = { [0] = "", "R", "V", "RV", "U", "RU", "VU", "RVU" },
  ["CONV  "] = setmetatable({}, { __index = function(t, mode)
    local s = irtype_text[band(mode, 31)]
    s = irtype_text[band(shr(mode, 5), 31)] .. "." .. s
    if band(mode, 0x800) ~= 0 then s = s .. " sext" end
    local c = shr(mode, 12)
    if c == 1 then s = s .. " none"
    elseif c == 2 then s = s .. " index"
    elseif c == 3 then s = s .. " check" end
    t[mode] = s
    return s
  end }),
  ["FLOAD "] = vmdef.irfield,
  ["FREF  "] = vmdef.irfield,
  ["FPMATH"] = vmdef.irfpm,
  ["BUFHDR"] = { [0] = "RESET", "APPEND", "WRITE" },
  ["TOSTR "] = { [0] = "INT", "NUM", "CHAR" },
}

local function trim(s)
  if s == nil then return nil end
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Decode a constant operand. `v` is the negative,
-- REF_BIAS-relative operand value returned by the harness; the
-- constant lives at kval[-v] / kot[-v]. Returns (txt, tab) like
-- ljopt_formatsmt.
local function decode_const(pass, v)
  local idx = -v
  local k = pass.kval[idx]
  if type(k) == "number" then
    return float_to_smt_bv(k), { type = "number", value = k }
  end
  -- Non-numeric constants are outside the v1 op set; fall back
  -- to a literal string so translation can mark the node NYI
  -- rather than crash.
  return tostring(k), nil
end

-- Decode one replay pass buffer into { trace = <nodes> }.
local function decode(pass)
  local irnames = vmdef.irnames
  local nodes = {}
  for i = 1, pass.nins do
    local ot = pass.ot[i]
    local m = pass.m[i]
    local op1, op2 = pass.op1[i], pass.op2[i]

    local oidx = 6 * shr(ot, 8)
    local op6 = irnames:sub(oidx + 1, oidx + 6)
    local irtype = irtype_text[band(ot, 31)]
    local guard = band(ot, 128) ~= 0
    local phi = band(ot, 64) ~= 0
    local raw = (guard and ">" or " ") .. (phi and "+" or " ")

    local m1, m2 = band(m, 3), band(m, 3 * 4)
    local op1_tab, op1_txt, op2_tab, op2_txt

    if m1 ~= 3 then -- op1 present
      if op1 < 0 then
        op1_txt, op1_tab = decode_const(pass, op1)
      elseif m1 == 0 then -- IRMref
        op1_tab = { type = "ssa", value = op1 }
        op1_txt = ("%04d"):format(op1)
      else -- IRMlit
        op1_tab = { type = "imm", value = op1 }
        op1_txt = ("#%d"):format(op1)
      end
    end

    if m2 ~= 3 * 4 then -- op2 present
      if m2 == 1 * 4 then -- IRMlit
        local litn = litname[op6]
        if litn and litn[op2] then
          -- literal-mode: no tab, txt carries it
          op2_txt = litn[op2]
        else
          op2_tab = { type = "imm", value = op2 }
          op2_txt = ("#%d"):format(op2)
        end
      elseif op2 < 0 then
        op2_txt, op2_tab = decode_const(pass, op2)
      else -- IRMref
        op2_tab = { type = "ssa", value = op2 }
        op2_txt = ("%04d"):format(op2)
      end
    end

    nodes[i] = {
      num = i,
      flags = {
        irt_guard = guard,
        irt_isphi = phi,
        irt_mark = false,
        raw = raw,
      },
      irtype = trim(irtype),
      irop = trim(op6),
      op1 = op1_tab,
      op1_txt = op1_txt and trim(op1_txt) or nil,
      op2 = op2_tab,
      op2_txt = op2_txt and trim(op2_txt) or nil,
    }
  end
  return { trace = nodes }
end

-- SMT bitvector literal (#x...) for a folded-constant ref (< 0)
-- in a pass buffer. Used to materialize a constant output into a
-- snapshot slot; ljopt's snap_to_smt_lib wraps it in
-- ((_ to_fp 11 53) ...), so an int constant k round-trips
-- through fp exactly (int32 fits in a double), matching the
-- int-node side's smt_int_to_fp.
local function const_smt_bv(pass, ref)
  local k = pass.kval[-ref]
  assert(type(k) == "number", "irfuzz: non-numeric constant output")
  return float_to_smt_bv(k)
end

return {
  decode = decode,
  const_smt_bv = const_smt_bv,
}
