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

local function inspect_stack_arguments(func)
    -- Get information about the function,
    -- including its current line.
    local info = debug.getinfo(func, "S")
    if not info then return end

    -- Get the active local variables (including arguments)
    -- at the given PC. Note: maybe we should track the
    -- whole stack not just single function.
    --
    -- level 1 is current function (inspect_stack_arguments)
    -- level 2 is previous function from ir_dump_utils
    -- level 3 is previous function from ir_dump
    -- level 4 is actual function caused trace recording
    local level = 4
    local i = 1
    local result = ""
    while true do
        local name, value = debug.getlocal(level, i)
        if not name then break end
        result = result .. string.format("(%s)", type(value))
        i = i + 1
    end
    return result
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

local function ljopt_init_new_trace(tr)
  dev_checks("number")
  local tr_id = get_trace_id(tr)
  if tr_id == nil then
    return
  end
  assert(exec_record[tr_id] == nil,
    "Trace with exactly this bytecode already exists " .. tr_id
  )
  exec_record[tr_id] = {}
  exec_record[tr_id].trace = {}
  exec_record[tr_id].snapshots = {}
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

-- @tr - trace
-- @snapno - snapshot number within the trace
-- Returns uid for the snapshot based on BC PC
-- Note: returned ID is persistent across executions
local function get_snap_uid(tr, snapno)
  return jutil.snappc(tr, snapno)
end

-- Trace id is:
-- 1. Current trace bytecode hash.
-- 2. Parent trace bytecode hash.
-- 3. Parent trace exit snapshot offset.
-- All of the above together gives unique ID
-- (except for cases, when there's multiple snapshots
--  with same ID, we'll ignore them for now).
local function ljopt_init_trace_uid(tr, func, pc, what, otr, oex)
  if what == "start" then
    local stringify_arguments = inspect_stack_arguments(func, pc)
    trace_bc_hash[tr] = ""
    dev_checks("number", "function", "number", "string")

    traces_num[tr] = tostring(fnv1a_hash(stringify_arguments))
    if otr then
      if traces_num[otr] ~= nil then
        -- Set parent <trace_id>_<snap_id>
        local parent_trace_id = get_trace_id(otr)
        traces_num[tr] = traces_num[tr] .. parent_trace_id
        if oex >= 0 then
          local snap_id = get_snap_uid(otr, oex)
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
      traces_num[tr] = traces_num[tr] .. "_" .. bc_hash
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

local function get_hmask(t)
  -- Count hash entries
  local hmask, asize = jutil.tablesize(t)
  return hmask, asize
end

-- Everything same as formatk except float conversion.
local function ljopt_formatsmt(tr, idx, sn)
  local k, t, slot = tracek(tr, idx)
  local tn = type(k)
  local s
  local const_type = nil
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
    -- TODO: const value should be printed and parsed
    -- later as well. For now only asize and hmask are supported.
    const_type = "table"
    local hmask, asize = get_hmask(k)
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
    end
  end
  if slot then
    s = format("%s @%d", s, slot)
  end
  -- Return whether this constant supported in Snapshot.
  -- Currently only num works.
  -- https://github.com/ligurio/ljopt/issues/36
  return s, {type = const_type, value = k}
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
        local smt_str, const_tab = ljopt_formatsmt(tr, ref, sn)
        if const_tab ~= nil
          and const_tab.type == "number"
          and string.sub(smt_str, 1, 2) == "#x" then
          table.insert(snapshot, {s, {
            type = "const",
            value = smt_str,
            const_type = const_tab.type,
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
  local snap_id = get_snap_uid(tr, snapno)
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
}
