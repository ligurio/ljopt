local jutil = require("jit.util")
local vmdef = require("jit.vmdef")
local jit = require("jit")
local funcinfo = jutil.funcinfo
local tracek = jutil.tracek
local bit = require("bit")
local band, shr = bit.band, bit.rshift
local sub, gsub, format = string.sub, string.gsub, string.format
local byte = string.byte

-- Disable JIT for ir_dump to not interfere with verification
-- traces.
jit.off(true, true)

-- IR dump helpers for SMT verification.
-----------------------------------------------------

-- A table with recorded execution.
--   trace : array<pair<SlotId, StackId>>
--   snapshots: table<LastInst, array<pair<SlotId, StackId>>>
local exec_record = {}

-- table<id, line_number>
local traces_num

local ffi = require("ffi")
local dev_checks = require('ljopt.dev_checks')

-- Get float in SMT format.
-- This is the most convenient way to store float, moreover,
-- float format used by ir_dump uses some rounding behaviour,
-- which is lead to incorrect verification
local function float_to_smt_bv(x)
  dev_checks("number")
  local u = ffi.new("union { double d; uint64_t i; }")
  u.d = x
  return string.format("#x%s", bit.tohex(u.i, 16))
end

local function ljopt_init_trace_state()
  exec_record = {}
  traces_num = {}
end

local function ljopt_get_execution_state()
  return exec_record
end

-- Returns persistent unique id across traces
-- @tr - trace
local function get_trace_id(tr)
  dev_checks("number")
  return traces_num[tr]
end

local function ljopt_init_new_trace(tr)
  dev_checks("number")
  local tr_id = get_trace_id(tr)
  assert(exec_record[tr_id] == nil)
  exec_record[tr_id] = {}
  exec_record[tr_id].trace = {}
  exec_record[tr_id].snapshots = {}
end

-- This function was copied from ir_dump
local function fmtfunc(func, pc)
  dev_checks("function", "number")
  local fi = funcinfo(func, pc)
  if fi.loc then
    return fi.loc
  elseif fi.ffid then
    return vmdef.ffnames[fi.ffid]
  elseif fi.addr then
    return format("C:%x", fi.addr)
  else
    return "(?)"
  end
end


-- Remember line where trace starts
local function ljopt_init_trace_uid(tr, func, pc, what)
  if what == "start" then
    dev_checks("number", "function", "number", "string")
    traces_num[tr] = tonumber(string.match(fmtfunc(func, pc), ":(%d+)"))
  end
end

-- @tr - trace
-- @snapno - snapshot number within the trace
-- Returns uid for the snapshot based on BC PC
-- Note: returned ID is persistent across executions
local function get_snap_uid(tr, snapno)
  return jutil.snappc(tr, snapno)
end

local function ctlsub(c)
  if c == "\n" then return "\\n"
  elseif c == "\r" then return "\\r"
  elseif c == "\t" then return "\\t"
  else return format("\\%03d", byte(c))
  end
end


-- Everything same as formatk except float conversion.
local function ljopt_formatsmt(tr, idx, sn)
  local k, t, slot = tracek(tr, idx)
  local tn = type(k)
  local s
  if tn == "number" then
    if t < 12 then
      s = k == 0 and "NULL" or format("[0x%08x]", k)
    elseif band(sn or 0, 0x30000) ~= 0 then
      s = band(sn, 0x20000) ~= 0 and "contpc" or "ftsz"
    elseif k == 2^52+2^51 then
      s = "bias"
    else
      -- luacheck: push no max_comment_line_length
      -- s = format(0 < k and k < 0x1p-1026 and "%+a" or "%+.14g", k)
      -- luacheck: pop
      s = float_to_smt_bv(k)
    end
  elseif tn == "string" then
    s = format(#k > 20 and '"%.20s"~' or '"%s"', gsub(k, "%c", ctlsub))
  elseif tn == "function" then
    s = fmtfunc(k)
  elseif tn == "table" then
    s = format("{%p}", k)
  elseif tn == "userdata" then
    if t == 12 then
      s = format("userdata:%p", k)
    else
      s = format("[%p]", k)
      if s == "[NULL]" then s = "NULL" end
    end
  elseif t == 21 then -- int64_t
    s = sub(tostring(k), 1, -3)
    if sub(s, 1, 1) ~= "-" then s = "+"..s end
  -- SNAP(1, SNAP_FRAME | SNAP_NORESTORE, REF_NIL)
  elseif sn == 0x1057fff then
    return "----" -- Special case for LJ_FR2 slot 1.
  else
    s = tostring(k) -- For primitives.
  end
  if slot then
    s = format("%s @%d", s, slot)
  end
  return s
end

-- Returns array<(snap_num, type, slot, Option(slot))>>
local function ljopt_savesnap(tr, nins, snap, snapno, linktype)
  if (linktype == "stitch") then
    -- stitch is not supported yet
    return
  end

  local snapshot = {}
  local n = 2
  for s=0,snap[1]-1 do
    local sn = snap[n]
    if shr(sn, 24) == s then
      n = n + 1
      local ref = band(sn, 0xffff) - 0x8000 -- REF_BIAS
      if ref < 0 then
        -- Type 1: Constant.
        table.insert(snapshot, {s, "const", ljopt_formatsmt(tr, ref, sn)})
      elseif band(sn, 0x80000) ~= 0 then
        -- Type 2: Soft-float number (needs two SSA slots).
        table.insert(snapshot, {s, "softfp", ref, ref+1})
      else
        -- Type 3: Regular SSA reference.
        table.insert(snapshot, {s, "ssa", ref})
      end
    end
  end
  local tr_id = get_trace_id(tr)
  local snap_id = get_snap_uid(tr, snapno)
  exec_record[tr_id].snapshots[snap_id] = {nins = nins, slots = snapshot}
end

local function trim(s)
  if s == nil then return end
  local ss, _ = s:gsub('^%s*(.-)%s*$', '%1')
  return ss
end


local function ljopt_savetrace(tr, ins, flags, irtype, op, op1, op2)
  -- The symbol ">" indicates the instruction of the
  -- guard's location
  -- (leading to possible side exits from the trace).
  local irt_guard = flags:sub(1, 1) == ">"
  -- The symbol "+" indicates the instruction is a
  -- left or right PHI operand.
  -- (i.e. referred to in some PHI instruction).
  local irt_isphi = flags:sub(2, 2) == "+"
  -- As stated in LuaJIT comment: `Marker for misc. purposes`.
  local irt_mark = flags:sub(1, 1) == "}"
  local irins = {
    num = ins,
    flags = {
      irt_guard = irt_guard,
      irt_isphi = irt_isphi,
      irt_mark = irt_mark,
      raw = flags
    },
    irtype = trim(irtype),
    irop = trim(op),
    op1 = trim(op1),
    op2 = trim(op2),
  }
  table.insert(exec_record[get_trace_id(tr)].trace, irins)
end

return {
  ljopt_init_trace_state = ljopt_init_trace_state,
  ljopt_get_execution_state = ljopt_get_execution_state,
  ljopt_init_new_trace = ljopt_init_new_trace,
  ljopt_init_trace_uid = ljopt_init_trace_uid,
  ljopt_savesnap = ljopt_savesnap,
  ljopt_savetrace = ljopt_savetrace,
  ljopt_formatsmt = ljopt_formatsmt,
}
