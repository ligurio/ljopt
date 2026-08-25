-- IR dump helpers for SMT verification.
--
-- This file is intentionally isolated from other files
-- to prevent changes to runtime behaviour during trace
-- recording.
-- Since this helper functions are called from JIT handlers,
-- isolating them ensures that modifications to other files
-- won't unexpectedly affect the recorded trace.
-----------------------------------------------------

local jutil = require("jit.util")
local tablesize = require("ljopt.jit_util").tablesize
local tracesnap = jutil.tracesnap
local vmdef = require("jit.vmdef")
local jit = require("jit")
local funcinfo, funcbc = jutil.funcinfo, jutil.funcbc
local bcline = require("jit.bc").line
local tracek = jutil.tracek
local ljopt_config = require("ljopt.config")
local bit = require("bit")
local band, shr = bit.band, bit.rshift
local sub, gsub, format = string.sub, string.gsub, string.format
local byte, rep = string.byte, string.rep

-- Disable JIT for ir_dump to not interfere with verification
-- traces.
jit.off(true, true)

-- This code called inside tested Lua chunk, so we still
-- have to isolate global variables by making their local copy.
local type = type

-- IRT_NUM/IRT_INT are derived from the irtype_text table owned by
-- ir_dump.lua and handed over via ljopt_init(), so the numbers
-- stay in sync with that table instead of being hardcoded.
-- See IRType and IRSLOAD_CONVERT in LuaJIT's lj_ir.h.
local IRT_NUM, IRT_INT
local IRSLOAD_CONVERT = 0x08

-- Receive tables owned by ir_dump.lua. Must be called before any
-- trace is processed.
local function ljopt_init(deps)
  -- Reverse map: type name -> IRType number.
  local irtypes = {}
  for num, name in ipairs(deps.irtype_text) do
    irtypes[name] = num
  end
  IRT_NUM = irtypes.num
  IRT_INT = irtypes.int
end

-- A narrowed slot is loaded as IRT_INT at -O3 (with the CONVERT
-- flag) but IRT_NUM at -O0, though the stack slot is a number in
-- both. Treat the two as equivalent only for such converting
-- loads, so the trace IDs match across opt levels without
-- conflating genuinely integer-typed slots.
-- See: https://github.com/ligurio/ljopt/issues/34
local function sload_type_token(irt, mode)
  if irt == IRT_INT and band(mode, IRSLOAD_CONVERT) ~= 0 then
    return IRT_NUM
  end
  return irt
end

-- Build type signature from SLOAD guards - these are the types
-- LJ specialized on at trace entry. Stable across opt levels for
-- the same Lua program.
local function sload_type_sig(tr)
  local info = jutil.traceinfo(tr)
  if not info then return "" end
  local sig = ""
  for i = 1, info.nins do
    local _, ot, op1, op2 = jutil.traceir(tr, i)
    local oidx = 6 * shr(ot, 8)
    local op = sub(vmdef.irnames, oidx + 1, oidx + 6)
    if op == "SLOAD " then
      local irt = sload_type_token(band(ot, 31), op2)
      sig = sig .. "_" .. tostring(op1) .. "t" .. tostring(irt)
    end
  end
  return sig
end

-- A table with recorded execution.
--   trace : array<pair<SlotId, StackId>>
--   snapshots: table<LastInst, array<pair<SlotId, StackId>>>
local exec_record = {}

-- table<id, line_number>
local traces_num

local trace_bc_hash

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
  trace_bc_hash = {}
end

local function ljopt_get_execution_state()
  return exec_record
end

-- Helper function used only in tests to map trace_id to
-- our internal persistent across launches ID.
local function ljopt_get_traceid_map()
  return traces_num
end

-- Returns persistent unique id across traces
-- @tr - trace
local function get_trace_id(tr)
  dev_checks("number")
  return traces_num[tr]
end

local function ljopt_init_new_trace(tr, linktype)
  dev_checks("number", "?string")
  local tr_id = get_trace_id(tr)
  if tr_id == nil then
    return
  end
  if exec_record[tr_id] ~= nil then
    -- Fingerprint collision: two LJ traces produced the same
    -- bytecode-hash + SLOAD-types signature. We can't pair
    -- them safely, however traces are (expected to be)
    -- equivalent, otherwise it's a bug in ljopt, in such
    -- case trace fingerprint should be extended.
    if ljopt_config.is_debug_mode() then
      io.stderr:write(
        "Skip duplicate trace fingerprint: " .. tr_id .. '\n'
      )
    end
    traces_num[tr] = nil
    return
  end
  exec_record[tr_id] = {}
  exec_record[tr_id].trace = {}
  exec_record[tr_id].snapshots = {}
  exec_record[tr_id].linktype = linktype
end

-- This function was copied from ir_dump
local function fmtfunc(func, pc)
  dev_checks("function", "?number")
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


local function fnv1a_hash(str)
  local hash = 2166136261
  for i = 1, #str do
    hash = bit.bxor(hash, string.byte(str, i))
    hash = (hash * 16777619) % 2^32
  end
  return string.format("%08x", hash)
end

local recprefix = ""
local recdepth = 0

local function ljopt_record_trace(traceno, func, pc, depth, _callee)
  if depth ~= recdepth then
    recdepth = depth
    recprefix = rep(" .", depth)
  end
  local line
  if pc >= 0 then
    line = bcline(func, pc, recprefix)
  else
    line = "0000 " .. recprefix .. " FUNCC      \n"
  end
  if pc >= 0 and band(funcbc(func, pc), 0xff) < 16 then
    line = line .. bcline(func, pc+1, recprefix)
  end
  if trace_bc_hash[traceno] then
    trace_bc_hash[traceno] = trace_bc_hash[traceno] .. ' ' .. line
  end
end

-- Trace id is:
-- 1. Current trace bytecode hash.
-- 2. Parent trace bytecode hash.
-- 3. Parent trace exit snapshot offset.
-- All of the above together gives unique ID
-- (except for cases, when there's multiple snapshots
--  with same ID, we'll ignore them for now).
local function ljopt_init_trace_uid(tr, _func, _pc, what, otr, oex)
  if what == "start" then
    trace_bc_hash[tr] = ""
    dev_checks("number", "function", "number", "string")
    traces_num[tr] = ""
    if otr then
      if traces_num[otr] ~= nil then
        -- Set parent <trace_id>_<snap_id>
        local parent_trace_id = get_trace_id(otr)
        traces_num[tr] = traces_num[tr] .. parent_trace_id
        if oex >= 0 then
          local _, snap_id = tracesnap(otr, oex, true)
          if #(exec_record[parent_trace_id].snapshots[snap_id].nins) == 1 then
            traces_num[tr] = traces_num[tr] .. "_" .. snap_id
          else
            -- Duplicated snapshot in parent.
            -- Ignore side traces.
            -- See: https://github.com/ligurio/ljopt/issues/30.
            traces_num[tr] = nil
          end
        end
      else
        -- Parent trace was removed, remove all children as well.
        traces_num[tr] = nil
      end
      -- Disable child traces.
      traces_num[tr] = nil
    end
  elseif what == "stop" or what == "abort" then
    if traces_num[tr] ~= nil then
      local bc_hash = tostring(fnv1a_hash(trace_bc_hash[tr]))
      traces_num[tr] = traces_num[tr] .. sload_type_sig(tr) .. "_" .. bc_hash
      if ljopt_config.is_debug_mode() then
        io.stderr:write("Cur trace id: " .. traces_num[tr] .. "\n")
      end
    else
      if ljopt_config.is_debug_mode() then
        io.stderr:write(
          "Skip trace, parent=nil, trace hash: " .. trace_bc_hash[tr] .. '\n'
        )
      end
    end
  end
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
  local const_type = nil
  -- Only set for a table constant: the parts a TDUP copies.
  local tab_asize, tab_hmask
  if tn == "number" then
    const_type = "number"
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
    const_type = "string"
    s = format(#k > 20 and '"%.20s"~' or '"%s"', gsub(k, "%c", ctlsub))
  elseif tn == "function" then
    const_type = "function"
    s = fmtfunc(k)
  elseif tn == "table" then
    const_type = "table"
    local hmask, asize = tablesize(k)
    tab_asize, tab_hmask = asize, hmask
    s = format("{%p:%d:%d}", k, asize, hmask)
  elseif tn == "userdata" then
    if t == 12 then
      s = format("userdata:%p", k)
    else
      s = format("[%p]", k)
      if s == "[NULL]" then s = "NULL" end
    end
  elseif t == 21 then -- int64_t
    const_type = "int64"
    s = "L" .. sub(tostring(k), 1, -3)
    if sub(s, 1, 1) ~= "-" then s = "+"..s end
  -- SNAP(1, SNAP_FRAME | SNAP_NORESTORE, REF_NIL)
  elseif sn == 0x1057fff then
    return "----" -- Special case for LJ_FR2 slot 1.
  else
    s = tostring(k) -- For primitives.
    if ffi.istype("int64_t", k) then
      const_type = "int64"
    elseif ffi.istype("uint64_t", k) then
      const_type = "uint64"
    elseif tn == "boolean" then
      const_type = "bool"
    end
  end
  if slot then
    s = format("%s @%d", s, slot)
  end
  -- Return whether this constant supported in Snapshot.
  -- Currently only num works.
  -- https://github.com/ligurio/ljopt/issues/36
  return s, {
    type = const_type, value = k,
    asize = tab_asize, hmask = tab_hmask,
  }
end

-- Returns array<(snap_num, type, slot, Option(slot))>>
local function ljopt_savesnap(tr, nins, snap, snapno, _linktype)
  local tr_id = get_trace_id(tr)
  if tr_id == nil then
    -- Skip this trace.
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
        local smt_str, const_tabs = ljopt_formatsmt(tr, ref, sn)
        if const_tabs ~= nil
          and const_tabs.type == "number"
          and string.sub(smt_str, 1, 2) == "#x" then
          table.insert(snapshot, {s, {
            type = "const",
            value = smt_str,
            const_type = const_tabs.type,
          }})
        elseif const_tabs ~= nil and const_tabs.type == "bool" then
          table.insert(snapshot, {s, {
            type = "const",
            value = tostring(const_tabs.value),
            const_type = const_tabs.type,
          }})
        end
      elseif band(sn, 0x80000) ~= 0 then
        -- Type 2: Soft-float number (needs two SSA slots).
        table.insert(snapshot, {s, {type="softfp", value=ref}})
      else
        -- Type 3: Regular SSA reference.
        table.insert(snapshot, {s, {type="ssa", value=ref}})
      end
    end
  end
  local _, snap_id = jutil.tracesnap(tr, snapno, true)
  assert(snap_id >= 0, "Snapshot ID must be positive")
  if ljopt_config.is_debug_mode() then
    io.stderr:write("Snap offset: " .. snap_id .. "\n")
  end
  if exec_record[tr_id].snapshots[snap_id] == nil then
    -- Do not support yet traces with more than 1
    -- snapshot with same offset.
    -- More details: https://github.com/ligurio/ljopt/issues/30
    exec_record[tr_id].snapshots[snap_id] = {nins = {nins}, slots = snapshot}
  else
    table.insert(exec_record[tr_id].snapshots[snap_id].nins, nins)
  end
  -- Save latest snapshot. It will be used in loops. Multiple
  -- snapshots at the same exit may still cause problems.
  exec_record[tr_id].snapshots[snap_id].last_slots = snapshot
end

local function trim(s)
  if s == nil then return end
  local ss, _ = gsub(s, '^%s*(.-)%s*$', '%1')
  return ss
end


local function ljopt_savetrace(tr, ins, flags, irtype, op,
                               op1, op2, op1_tab, op2_tab)
  local tr_id = get_trace_id(tr)
  if tr_id == nil then
    -- Skip this trace.
    return
  end

  assert(irtype ~= nil, "Unknown IR type.")

  -- The symbol ">" indicates the instruction of the
  -- guard's location
  -- (leading to possible side exits from the trace).
  local irt_guard = string.sub(flags, 1, 1) == ">"
  -- The symbol "+" indicates the instruction is a
  -- left or right PHI operand.
  -- (i.e. referred to in some PHI instruction).
  local irt_isphi = string.sub(flags, 2, 2) == "+"
  -- As stated in LuaJIT comment: `Marker for misc. purposes`.
  local irt_mark = string.sub(flags, 1, 1) == "}"
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
    -- op1 / op2: structured {type, value} tables
    -- for the operands (or nil).
    op1 = op1_tab,
    op2 = op2_tab,
    -- op1_txt / op2_txt: raw display strings for
    -- the operands (trimmed). These are needed for
    -- literal-mode operands (field names, mode flags,
    -- slot numbers with '#' prefix, etc.) that
    -- have no constant table.
    op1_txt = trim(op1),
    op2_txt = trim(op2),
  }
  if exec_record[tr_id] ~= nil then
    -- Otherwise this trace was removed due to Snapshot
    -- duplication.
    table.insert(exec_record[tr_id].trace, irins)
  end
end

return {
  ljopt_init_trace_state = ljopt_init_trace_state,
  ljopt_get_execution_state = ljopt_get_execution_state,
  ljopt_get_traceid_map = ljopt_get_traceid_map,
  ljopt_init_new_trace = ljopt_init_new_trace,
  ljopt_init_trace_uid = ljopt_init_trace_uid,
  ljopt_savesnap = ljopt_savesnap,
  ljopt_record_trace = ljopt_record_trace,
  ljopt_savetrace = ljopt_savetrace,
  ljopt_formatsmt = ljopt_formatsmt,
  ljopt_init = ljopt_init,
}
