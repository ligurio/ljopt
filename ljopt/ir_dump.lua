----------------------------------------------------------------------------
-- LuaJIT compiler dump module.
--
-- Copyright (C) 2005-2017 Mike Pall. All rights reserved.
-- Released under the MIT license. See Copyright Notice in luajit.h
----------------------------------------------------------------------------
--
-- This module can be used to debug the JIT compiler itself. It dumps the
-- code representations and structures used in various compiler stages.
------------------------------------------------------------------------------

-- Cache some library functions and objects.
local jit = require("jit")
assert(jit.version_num == 20100, "LuaJIT core/library version mismatch")
local jutil = require("jit.util")
local vmdef = require("jit.vmdef")
local funcinfo = jutil.funcinfo
local traceinfo, traceir, tracek = jutil.traceinfo, jutil.traceir, jutil.tracek
local tracesnap = jutil.tracesnap
local bit = require("bit")
local band, shr = bit.band, bit.rshift
local sub, gsub, format = string.sub, string.gsub, string.format
local byte = string.byte
local type, tostring = type, tostring

-- Load other modules on-demand.
local disass

-- Active flag, output file handle and dump mode.
local active, out, dumpmode

------------------------------------------------------------------------------

local irtype_text = {
  [0] = "nil",
  "fal",
  "tru",
  "lud",
  "str",
  "p32",
  "thr",
  "pro",
  "fun",
  "p64",
  "cdt",
  "tab",
  "udt",
  "flt",
  "num",
  "i8 ",
  "u8 ",
  "i16",
  "u16",
  "int",
  "u32",
  "i64",
  "u64",
  "sfp",
}

local function colorize_text(s)
  return s
end

local colorize, irtype

-- Lookup tables to convert some literals into names.
local litname = {
  ["SLOAD "] = setmetatable({}, { __index = function(t, mode)
    local s = ""
    if band(mode, 1) ~= 0 then s = s.."P" end
    if band(mode, 2) ~= 0 then s = s.."F" end
    if band(mode, 4) ~= 0 then s = s.."T" end
    if band(mode, 8) ~= 0 then s = s.."C" end
    if band(mode, 16) ~= 0 then s = s.."R" end
    if band(mode, 32) ~= 0 then s = s.."I" end
    t[mode] = s
    return s
  end}),
  ["XLOAD "] = { [0] = "", "R", "V", "RV", "U", "RU", "VU", "RVU", },
  ["CONV  "] = setmetatable({}, { __index = function(t, mode)
    local s = irtype[band(mode, 31)]
    s = irtype[band(shr(mode, 5), 31)].."."..s
    if band(mode, 0x800) ~= 0 then s = s.." sext" end
    local c = shr(mode, 14)
    if c == 2 then s = s.." index" elseif c == 3 then s = s.." check" end
    t[mode] = s
    return s
  end}),
  ["FLOAD "] = vmdef.irfield,
  ["FREF  "] = vmdef.irfield,
  ["FPMATH"] = vmdef.irfpm,
  ["BUFHDR"] = { [0] = "RESET", "APPEND" },
  ["TOSTR "] = { [0] = "INT", "NUM", "CHAR" },
}

local function ctlsub(c)
  if c == "\n" then return "\\n"
  elseif c == "\r" then return "\\r"
  elseif c == "\t" then return "\\t"
  else return format("\\%03d", byte(c))
  end
end

local function fmtfunc(func, pc)
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

local function formatk(tr, idx, sn)
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
      s = format(0 < k and k < 0x1p-1026 and "%+a" or "%+.14g", k)
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
  elseif sn == 0x1057fff then -- SNAP(1, SNAP_FRAME | SNAP_NORESTORE, REF_NIL)
    return "----" -- Special case for LJ_FR2 slot 1.
  else
    s = tostring(k) -- For primitives.
  end
  s = colorize(format("%-4s", s), t)
  if slot then
    s = format("%s @%d", s, slot)
  end
  return s
end

local function printsnap(tr, snap)
  local n = 2
  for s=0,snap[1]-1 do
    local sn = snap[n]
    if shr(sn, 24) == s then
      n = n + 1
      local ref = band(sn, 0xffff) - 0x8000 -- REF_BIAS
      if ref < 0 then
	out:write(formatk(tr, ref, sn))
      elseif band(sn, 0x80000) ~= 0 then -- SNAP_SOFTFPNUM
	out:write(colorize(format("%04d/%04d", ref, ref+1), 14))
      else
	local _, ot, _, _ = traceir(tr, ref)
	out:write(colorize(format("%04d", ref), band(ot, 31)))
      end
      out:write(band(sn, 0x10000) == 0 and " " or "|") -- SNAP_FRAME
    else
      out:write("---- ")
    end
  end
  out:write("]\n")
end

-- Dump snapshots (not interleaved with IR).
local function dump_snap(tr)
  out:write("---- TRACE ", tr, " snapshots\n")
  for i=0,1000000000 do
    local snap = tracesnap(tr, i)
    if not snap then break end
    out:write(format("#%-3d %04d [ ", i, snap[0]))
    printsnap(tr, snap)
  end
end

-- Return a register name or stack slot for a rid/sp location.
local function ridsp_name(ridsp, ins)
  if not disass then disass = require("jit.dis_"..jit.arch) end
  local rid, slot = band(ridsp, 0xff), shr(ridsp, 8)
  if rid == 253 or rid == 254 then
    return (slot == 0 or slot == 255) and " {sink" or format(" {%04d", ins-slot)
  end
  if ridsp > 255 then return format("[%x]", slot*4) end
  if rid < 128 then return disass.regname(rid) end
  return ""
end

-- Dump CALL* function ref and return optional ctype.
local function dumpcallfunc(tr, ins)
  local ctype
  if ins > 0 then
    local _, ot, op1, op2 = traceir(tr, ins)
    if band(ot, 31) == 0 then -- nil type means CARG(func, ctype).
      ins = op1
      ctype = formatk(tr, op2)
    end
  end
  if ins < 0 then
    out:write(format("[0x%x](", tonumber((tracek(tr, ins)))))
  else
    out:write(format("%04d (", ins))
  end
  return ctype
end

-- Recursively gather CALL* args and dump them.
local function dumpcallargs(tr, ins)
  if ins < 0 then
    out:write(formatk(tr, ins))
  else
    local _, ot, op1, op2 = traceir(tr, ins)
    local oidx = 6*shr(ot, 8)
    local op = sub(vmdef.irnames, oidx+1, oidx+6)
    if op == "CARG  " then
      dumpcallargs(tr, op1)
      if op2 < 0 then
	out:write(" ", formatk(tr, op2))
      else
	out:write(" ", format("%04d", op2))
      end
    else
      out:write(format("%04d", ins))
    end
  end
end

-- Dump IR and interleaved snapshots.
local function dump_ir(tr, dumpsnap, dumpreg)
  local info = traceinfo(tr)
  if not info then return end
  local nins = info.nins
  out:write("---- TRACE ", tr, " IR\n")
  local irnames = vmdef.irnames
  local snapref = 65536
  local snap, snapno
  if dumpsnap then
    snap = tracesnap(tr, 0)
    snapref = snap[0]
    snapno = 0
  end
  for ins=1,nins do
    if ins >= snapref then
      if dumpreg then
	out:write(format("....              SNAP   #%-3d [ ", snapno))
      else
	out:write(format("....        SNAP   #%-3d [ ", snapno))
      end
      printsnap(tr, snap)
      snapno = snapno + 1
      snap = tracesnap(tr, snapno)
      snapref = snap and snap[0] or 65536
    end
    local m, ot, op1, op2, ridsp = traceir(tr, ins)
    local oidx, t = 6*shr(ot, 8), band(ot, 31)
    local op = sub(irnames, oidx+1, oidx+6)
    if op == "LOOP  " then
      if dumpreg then
	out:write(format("%04d ------------ LOOP ------------\n", ins))
      else
	out:write(format("%04d ------ LOOP ------------\n", ins))
      end
    elseif op ~= "NOP   " and op ~= "CARG  " and
	   (dumpreg or op ~= "RENAME") then
      local rid = band(ridsp, 255)
      if dumpreg then
	out:write(format("%04d %-6s", ins, ridsp_name(ridsp, ins)))
      else
	out:write(format("%04d ", ins))
      end
      out:write(format("%s%s %s %s ",
		       (rid == 254 or rid == 253) and "}" or
		       (band(ot, 128) == 0 and " " or ">"),
		       band(ot, 64) == 0 and " " or "+",
		       irtype[t], op))
      local m1, m2 = band(m, 3), band(m, 3*4)
      if sub(op, 1, 4) == "CALL" then
	local ctype
	if m2 == 1*4 then -- op2 == IRMlit
	  out:write(format("%-10s  (", vmdef.ircall[op2]))
	else
	  ctype = dumpcallfunc(tr, op2)
	end
	if op1 ~= -1 then dumpcallargs(tr, op1) end
	out:write(")")
	if ctype then out:write(" ctype ", ctype) end
      elseif op == "CNEW  " and op2 == -1 then
	out:write(formatk(tr, op1))
      elseif m1 ~= 3 then -- op1 != IRMnone
	if op1 < 0 then
	  out:write(formatk(tr, op1))
	else
	  out:write(format(m1 == 0 and "%04d" or "#%-3d", op1))
	end
	if m2 ~= 3*4 then -- op2 != IRMnone
	  if m2 == 1*4 then -- op2 == IRMlit
	    local litn = litname[op]
	    if litn and litn[op2] then
	      out:write("  ", litn[op2])
	    elseif op == "UREFO " or op == "UREFC " then
	      out:write(format("  #%-3d", shr(op2, 8)))
	    else
	      out:write(format("  #%-3d", op2))
	    end
	  elseif op2 < 0 then
	    out:write("  ", formatk(tr, op2))
	  else
	    out:write(format("  %04d", op2))
	  end
	end
      end
      out:write("\n")
    end
  end
  if snap then
    if dumpreg then
      out:write(format("....              SNAP   #%-3d [ ", snapno))
    else
      out:write(format("....        SNAP   #%-3d [ ", snapno))
    end
    printsnap(tr, snap)
  end
end

------------------------------------------------------------------------------

-- Format trace error message.
local function fmterr(err, info)
  if type(err) == "number" then
    if type(info) == "function" then info = fmtfunc(info) end
    err = format(vmdef.traceerr[err], info)
  end
  return err
end

-- Dump trace states.
local function dump_trace(what, tr, func, pc, otr, oex)
  if what == "stop" or (what == "abort" and dumpmode.a) then
    if dumpmode.i then dump_ir(tr, dumpmode.s, dumpmode.r and what == "stop")
    elseif dumpmode.s then dump_snap(tr) end
  end
  if what == "start" then
    out:write("---- TRACE ", tr, " ", what)
    if otr then out:write(" ", otr, "/", oex == -1 and "stitch" or oex) end
    out:write(" ", fmtfunc(func, pc), "\n")
  elseif what == "stop" or what == "abort" then
    out:write("---- TRACE ", tr, " ", what)
    if what == "abort" then
      out:write(" ", fmtfunc(func, pc), " -- ", fmterr(otr, oex), "\n")
    else
      local info = traceinfo(tr)
      local link, ltype = info.link, info.linktype
      if link == tr or link == 0 then
	out:write(" -> ", ltype, "\n")
      elseif ltype == "root" then
	out:write(" -> ", link, "\n")
      else
	out:write(" -> ", link, " ", ltype, "\n")
      end
    end
  else
    out:write("---- TRACE ", what, "\n\n")
  end
  out:flush()
end

-- Detach dump handlers.
local function dumpoff()
  if active then
    active = false
    jit.attach(dump_trace)
    if out then out:close() end
    out = nil
  end
end

-- Open the output file and attach dump handlers.
local function dumpon(outfile)
  if active then dumpoff() end
  dumpmode = { t=true, b=true, i=true, m=false }
  jit.attach(dump_trace, "trace")
  colorize = colorize_text
  irtype = irtype_text
  active = true
  out = outfile or io.stdout
end

local function record(lua_code)
  -- Lua treats any independent chunk as the body of an anonymous function.
  -- For instance, for the chunk "a = 1", loadstring returns the equivalent
  -- of `function () a = 1 end`, https://www.lua.org/pil/8.html
  local fn, err = loadstring(lua_code)
  if fn == nil then
    error(("cannot load Lua code: %s"):format(err))
  end

  local traces = {}
  dumpon()
  pcall(fn)
  dumpoff()

  table.insert(traces, {})

  return traces
end

return {
  record = record,
}
