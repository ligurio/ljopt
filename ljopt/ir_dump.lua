----------------------------------------------------------------------------
-- LuaJIT compiler dump module.
--
-- Copyright (C) 2005-2025 Mike Pall. All rights reserved.
-- Released under the MIT license. See Copyright Notice in luajit.h
----------------------------------------------------------------------------
--
-- This module can be used to debug the JIT compiler itself. It dumps the
-- code representations and structures used in various compiler stages.
------------------------------------------------------------------------------

-- Cache some library functions and objects.
local jit = require("jit")
local jutil = require("jit.util")
local vmdef = require("jit.vmdef")
local funcinfo, funcbc = jutil.funcinfo, jutil.funcbc
local traceinfo, traceir, tracek = jutil.traceinfo, jutil.traceir, jutil.tracek
local tracesnap = jutil.tracesnap
local bit = require("bit")
local band, shr, tohex = bit.band, bit.rshift, bit.tohex
local sub, gsub, format = string.sub, string.gsub, string.format
local byte, rep = string.byte, string.rep
local type, tostring = type, tostring

local ir_dump_utils = require('ljopt.ir_dump_utils')

-- Disable JIT for ir_dump to not interfere with verification
-- traces.
jit.off(true, true)

-- Load other modules on-demand.
local bcline, disass

-- Active flag, output file handle and dump mode.
local active, out, dumpmode

-- Debug mode.
local debug_mode = false

local function write_out(...)
  assert(out)
  if not debug_mode then return end
  out:write(...)
end

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
    if band(mode, 64) ~= 0 then s = s.."K" end
    t[mode] = s
    return s
  end}),
  ["XLOAD "] = { [0] = "", "R", "V", "RV", "U", "RU", "VU", "RVU", },
  ["CONV  "] = setmetatable({}, { __index = function(t, mode)
    local s = irtype[band(mode, 31)]
    s = irtype[band(shr(mode, 5), 31)].."."..s
    if band(mode, 0x800) ~= 0 then s = s.." sext" end
    local c = shr(mode, 12)
    if c == 1 then s = s.." none"
    elseif c == 2 then s = s.." index"
    elseif c == 3 then s = s.." check" end
    t[mode] = s
    return s
  end}),
  ["FLOAD "] = vmdef.irfield,
  ["FREF  "] = vmdef.irfield,
  ["FPMATH"] = vmdef.irfpm,
  ["TMPREF"] = { [0] = "", "IN", "OUT", "INOUT", "", "", "OUT2", "INOUT2" },
  ["BUFHDR"] = { [0] = "RESET", "APPEND", "WRITE" },
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
  s = colorize(format("%-4s", s), t, band(sn or 0, 0x100000) ~= 0)
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
	write_out(formatk(tr, ref, sn))
      elseif band(sn, 0x80000) ~= 0 then -- SNAP_SOFTFPNUM
	write_out(colorize(format("%04d/%04d", ref, ref+1), 14))
      else
	local _, ot, _, _ = traceir(tr, ref)
	write_out(colorize(format("%04d", ref), band(ot, 31)))
      end
      write_out(band(sn, 0x10000) == 0 and " " or "|") -- SNAP_FRAME
    else
      write_out("---- ")
    end
  end
  write_out("]\n")
end

-- Dump snapshots (not interleaved with IR).
local function dump_snap(tr)
  write_out("---- TRACE ", tr, " snapshots\n")
  for i=0,1000000000 do
    local snap = tracesnap(tr, i)
    if not snap then break end
    write_out(format("#%-3d %04d [ ", i, snap[0]))
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
    write_out(format("[0x%x](", tonumber((tracek(tr, ins)))))
  else
    write_out(format("%04d (", ins))
  end
  return ctype
end

-- Recursively gather CALL* args and dump them.
local function dumpcallargs(tr, ins)
  local args = {}
  if ins < 0 then
    local txt, tab = ir_dump_utils.ljopt_formatsmt(tr, ins)
    args[#args + 1] = {txt = txt, tab = tab}
    write_out(formatk(tr, ins))
  else
    local _, ot, op1, op2 = traceir(tr, ins)
    local oidx = 6*shr(ot, 8)
    local op = sub(vmdef.irnames, oidx+1, oidx+6)
    if op == "CARG  " then
      local sub_args = dumpcallargs(tr, op1)
      for i = 1, #sub_args do args[#args + 1] = sub_args[i] end
      if op2 < 0 then
	write_out(" ", formatk(tr, op2))
  local txt, tab = ir_dump_utils.ljopt_formatsmt(tr, op2)
  args[#args + 1] = {txt = txt, tab = tab}
      else
	write_out(" ", format("%04d", op2))
  args[#args + 1] = {
    txt = format("%04d", op2),
    tab = {type = "ssa", value = op2}
  }
      end
    else
      write_out(format("%04d", ins))
      args[#args + 1] = {
        txt = format("%04d", ins),
        tab = {type = "ssa", value = ins}
      }
    end
  end
  return args
end

-- Dump IR and interleaved snapshots.
local function dump_ir(tr, dumpsnap, dumpreg)
  local info = traceinfo(tr)
  if not info then return end
  local nins = info.nins
  write_out("---- TRACE ", tr, " IR\n")

  ir_dump_utils.ljopt_init_new_trace(tr)
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
      ir_dump_utils.ljopt_savesnap(tr, ins, snap, snapno, info.linktype)
    end
    if ins >= snapref then
      if dumpreg then
	write_out(format("....              SNAP   #%-3d [ ", snapno))
      else
	write_out(format("....        SNAP   #%-3d [ ", snapno))
      end
      printsnap(tr, snap)
      snapno = snapno + 1
      snap = tracesnap(tr, snapno)
      snapref = snap and snap[0] or 65536
    end
    local m, ot, op1, op2, ridsp = traceir(tr, ins)
    local oidx, t = 6*shr(ot, 8), band(ot, 31)
    local op = sub(irnames, oidx+1, oidx+6)
    local op1_txt, op2_txt, op1_tab, op2_tab
    local rid
    if op == "LOOP  " then
      if dumpreg then
	write_out(format("%04d ------------ LOOP ------------\n", ins))
      else
	write_out(format("%04d ------ LOOP ------------\n", ins))
      end
    elseif op ~= "NOP   " and op ~= "CARG  " and
	   (dumpreg or op ~= "RENAME") then
      rid = band(ridsp, 255)
      if dumpreg then
	write_out(format("%04d %-6s", ins, ridsp_name(ridsp, ins)))
      else
	write_out(format("%04d ", ins))
      end
      write_out(format("%s%s %s %s ",
		       (rid == 254 or rid == 253) and "}" or
		       (band(ot, 128) == 0 and " " or ">"),
		       band(ot, 64) == 0 and " " or "+",
		       irtype[t], op))
      local m1, m2 = band(m, 3), band(m, 3*4)
      if sub(op, 1, 4) == "CALL" then
	local ctype
	if m2 == 1*4 then -- op2 == IRMlit
	  op2_txt = vmdef.ircall[op2]
	  write_out(format("%-10s  (", op2_txt))
	  -- Capture argument for ljopt: resolve CARG chain.
	  if op1 >= 0 then
	    local _, a_ot = traceir(tr, op1)
	    local a_oidx = 6*shr(a_ot, 8)
	    local a_op = sub(irnames, a_oidx+1, a_oidx+6)
	    if a_op ~= "CARG  " then
	      op1_tab = {type = "ssa", value = op1}
	      op1_txt = format("%04d", op1)
	    end
	  elseif op1 < 0 and op1 ~= -1 then
	    op1_txt, op1_tab = ir_dump_utils.ljopt_formatsmt(tr, op1)
	  end
	else
	  ctype = dumpcallfunc(tr, op2)
	end
	if op1 ~= -1 then
	  local call_args = dumpcallargs(tr, op1)
	  op1_tab = {type = "carg", value = call_args}
	  local parts = {}
	  for ai = 1, #call_args do parts[ai] = call_args[ai].txt end
	  op1_txt = table.concat(parts, " ")
	end
	write_out(")")
	if ctype then write_out(" ctype ", ctype) end
      elseif op == "CNEW  " and op2 == -1 then
	op1_txt, op1_tab = ir_dump_utils.ljopt_formatsmt(tr, op1)
	write_out(op1_txt)
      elseif m1 ~= 3 then -- op1 != IRMnone
	if op1 < 0 then
	  op1_txt, op1_tab = ir_dump_utils.ljopt_formatsmt(tr, op1)
	  write_out(op1_txt)
    assert(op1_tab ~= nil)
	else
	  op1_txt = format(m1 == 0 and "%04d" or "#%-3d", op1)
    op1_tab = {type = m1 == 0 and "ssa" or "imm", value = op1}
	  write_out(op1_txt)
	end
	if m2 ~= 3*4 then -- op2 != IRMnone
	  if m2 == 1*4 then -- op2 == IRMlit
	    local litn = litname[op]
	    if litn and litn[op2] then
	      op2_txt = litn[op2]
	      write_out("  ", op2_txt)
	    elseif op == "UREFO " or op == "UREFC " then
	      op2_txt = format("  #%-3d", shr(op2, 8))
	      write_out(op2_txt)
	    else
	      op2_txt = format("  #%-3d", op2)
          op2_tab = {type = "imm", value = op2}
	      write_out(op2_txt)
	    end
	  elseif op2 < 0 then
	    op2_txt, op2_tab = ir_dump_utils.ljopt_formatsmt(tr, op2)
	    write_out("  ", op2_txt)
	  else
	    op2_txt = format("  %04d", op2)
      op2_tab = {type="ssa", value=op2}
	    write_out(op2_txt)
	  end
	end
      end
      write_out("\n")
    end

    local flags = format("%s%s",
		       (rid == 254 or rid == 253) and "}" or
		       (band(ot, 128) == 0 and " " or ">"),
		       band(ot, 64) == 0 and " " or "+")
    ir_dump_utils.ljopt_savetrace(
      tr, ins, flags, irtype[t], op, op1_txt, op2_txt, op1_tab, op2_tab
    )
  end
  if snap then
    ir_dump_utils.ljopt_savesnap(tr, nins, snap, snapno, info.linktype)
    if dumpreg then
      write_out(format("....              SNAP   #%-3d [ ", snapno))
    else
      write_out(format("....        SNAP   #%-3d [ ", snapno))
    end
    printsnap(tr, snap)
  end
end

------------------------------------------------------------------------------

local recprefix = ""
local recdepth = 0
-- Format trace error message.
local function fmterr(err, info)
  if type(err) == "number" then
    if type(info) == "function" then info = fmtfunc(info) end
    local fmt = vmdef.traceerr[err]
    if fmt == "NYI: bytecode %s" then
      local oidx = 6 * info
      info = sub(vmdef.bcnames, oidx+1, oidx+6)
    end
    err = format(fmt, info)
  end
  return err
end

-- Dump trace states.
local function dump_trace(what, tr, func, pc, otr, oex)
  ir_dump_utils.ljopt_init_trace_uid(tr, func, pc, what, otr, oex)
  if what == "stop" or (what == "abort" and dumpmode.a) then
    if dumpmode.i then dump_ir(tr, dumpmode.s, dumpmode.r and what == "stop")
    elseif dumpmode.s then dump_snap(tr) end
  end
  if what == "start" then
    write_out("---- TRACE ", tr, " ", what)
    if otr then write_out(" ", otr, "/", oex == -1 and "stitch" or oex) end
    write_out(" ", fmtfunc(func, pc), "\n")
  elseif what == "stop" or what == "abort" then
    write_out("---- TRACE ", tr, " ", what)
    if what == "abort" then
      write_out(" ", fmtfunc(func, pc), " -- ", fmterr(otr, oex), "\n")
    else
      local info = traceinfo(tr)
      local link, ltype = info.link, info.linktype
      if link == tr or link == 0 then
	write_out(" -> ", ltype, "\n")
      elseif ltype == "root" then
	write_out(" -> ", link, "\n")
      else
	write_out(" -> ", link, " ", ltype, "\n")
      end
    end
  else
    write_out("---- TRACE ", what, "\n\n")
  end
  out:flush()
end

-- Dump recorded bytecode.
local function dump_record(tr, func, pc, depth, callee)
  ir_dump_utils.ljopt_record_trace(tr, func, pc, depth, callee)
  if depth ~= recdepth then
    recdepth = depth
    recprefix = rep(" .", depth)
  end
  local line
  if pc >= 0 then
    line = bcline(func, pc, recprefix)
  else
    line = "0000 "..recprefix.." FUNCC      \n"
  end
  if pc <= 0 then
    write_out(sub(line, 1, -2), "         ; ", fmtfunc(func), "\n")
  else
    write_out(line)
  end
  if pc >= 0 and band(funcbc(func, pc), 0xff) < 16 then -- ORDER BC
    write_out(bcline(func, pc+1, recprefix)) -- Write JMP for cond.
  end
end

------------------------------------------------------------------------------

local gpr64 = jit.arch:match("64")
local fprmips32 = jit.arch == "mips" or jit.arch == "mipsel"

-- Dump taken trace exits.
local function dump_texit(tr, ex, ngpr, nfpr, ...) -- luacheck: no unused
  out:write("---- TRACE ", tr, " exit ", ex, "\n")
  if dumpmode.X then
    local regs = {...}
    if gpr64 then
      for i=1,ngpr do
	out:write(format(" %016x", regs[i]))
	if i % 4 == 0 then out:write("\n") end
      end
    else
      for i=1,ngpr do
	out:write(" ", tohex(regs[i]))
	if i % 8 == 0 then out:write("\n") end
      end
    end
    if fprmips32 then
      for i=1,nfpr,2 do
	out:write(format(" %+17.14g", regs[ngpr+i]))
	if i % 8 == 7 then out:write("\n") end
      end
    else
      for i=1,nfpr do
	out:write(format(" %+17.14g", regs[ngpr+i]))
	if i % 4 == 0 then out:write("\n") end
      end
    end
  end
end

------------------------------------------------------------------------------
-- Detach dump handlers.
local function dumpoff()
  if active then
    active = false
    jit.attach(dump_trace)
    jit.attach(dump_record)
    if out then out:close() end
    out = nil
  end
end

-- Open the output file and attach dump handlers.
local function dumpon(outfile)
  if active then dumpoff() end
  -- Flush JIT so we'll have consistent
  -- trace numbers across recordings.
  jit.flush()
  dumpmode = { t=true, b=true, i=true, m=false, s=true, r=false }
  jit.attach(dump_trace, "trace")
  jit.attach(dump_record, "record")
  if not bcline then bcline = require("jit.bc").line end
  colorize = colorize_text
  irtype = irtype_text
  active = true
  out = outfile or io.stderr
end

local function record(fn, opt, is_debug_mode)
  debug_mode = is_debug_mode or os.getenv("LJOPT_DEBUG")
  ir_dump_utils.ljopt_init_trace_state()

  if opt == nil then
      opt = "jit.opt.start(0, 'hotloop=1', 'hotexit=1')"
  end
  assert(load(opt))()

  dumpon()
  pcall(fn)
  dumpoff()

  return ir_dump_utils.ljopt_get_execution_state()
end

return {
  record = record,
}
