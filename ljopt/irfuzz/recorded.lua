-- Lua chunks that drive the optimizer through its *recorder*
-- entry points.
--
-- Everything else in irfuzz feeds a synthetic instruction stream
-- straight to the fold engine, which is what makes it exhaustive
-- and reproducible. The price is that it can only reach code the
-- fold engine calls. A large part of the optimizer is not called
-- from there at all:
--
--   lj_opt_narrow.c   every entry but narrow_convert is invoked
--                     by lj_record.c / lj_ffrecord.c while a
--                     trace is being recorded
--   lj_opt_mem.c      lj_opt_fwd_wasnonnil is called by the
--                     recorder's index path, never by a fold rule
--   lj_opt_fold.c     the rules keyed on TDUP, HREFK, KSLOT and
--                     cdata constants need operands only the
--                     recorder interns
--
-- These chunks exist to run that half. Each is compiled by the
-- real JIT at -O3, so it is the recorder, not this file, that
-- decides which IR appears -- which also keeps them honest: a
-- chunk that stops being compiled stops contributing, and the
-- driver reports how many traces each one produced.
--
-- Kept deliberately small and side-effect free: they are run for
-- coverage, and every one of them must terminate quickly.

local chunks = {}

local function add(name, code)
  chunks[#chunks + 1] = { name = name, code = code }
end

-- lj_opt_narrow: narrow_forl on the loop variable, and the
-- int/num arithmetic the loop body narrows back to integers.
add("forl_int", [[
local s = 0
for i = 1, 200 do s = s + i * 2 - 1 end
return s
]])

add("forl_num", [[
local s = 0.0
for i = 1.5, 200.5 do s = s + i end
return s
]])

add("forl_step", [[
local s = 0
for i = 200, 1, -3 do s = s + i end
return s
]])

-- narrow_index / lj_opt_fwd_wasnonnil / ABC / HREFK: array and
-- hash indexing with a loop-carried key.
add("index_array", [[
local t = {}
for i = 1, 200 do t[i] = i * 2 end
local s = 0
for i = 2, 200 do s = s + t[i] + t[i - 1] end
return s
]])

add("index_hash", [[
local t = { a = 1, b = 2 }
local s = 0
for i = 1, 200 do s = s + t.a + t.b end
t.c = 3
for i = 1, 200 do s = s + t.c end
return s
]])

add("index_nil", [[
local t = {}
local s = 0
for i = 1, 200 do
  t[i] = nil
  if t[i] == nil then s = s + 1 end
end
return s
]])

-- narrow_tobit: the bit library takes its arguments through
-- lj_opt_narrow_tobit.
add("bitops", [[
local bit = require("bit")
local s = 0
for i = 1, 200 do
  s = bit.bxor(bit.band(s + i, 0xff), bit.lshift(i, 3))
  s = bit.bor(bit.rshift(s, 2), bit.bswap(i))
  s = bit.tobit(s + 1)
end
return s
]])

-- narrow_toint: the string library rounds its integer arguments
-- through lj_opt_narrow_toint.
add("strops", [[
local s = "abcdefghij"
local n = 0
for i = 1, 200 do
  local a = s:sub(1 + (i % 5), 6)
  n = n + #a + s:byte(1 + (i % 5)) + #string.rep("x", i % 4)
  n = n + #string.char(65 + (i % 20))
end
return n
]])

-- Buffer chains: concatenation and string.format record as
-- BUFHDR/BUFPUT/CALLL/BUFSTR.
add("concat", [[
local out = 0
for i = 1, 200 do
  local s = "a" .. "b" .. tostring(i % 7) .. "c"
  out = out + #s + #string.format("%d:%s:%5.2f", i, "k", i * 0.5)
  out = out + #("x"):rep(i % 3) + #("AbC"):upper() + #("AbC"):lower()
end
return out
]])

-- narrow_mod / narrow_unm: `%` and unary minus have their own
-- narrowing entry points.
add("mod_unm", [[
local s = 0
for i = 1, 200 do
  s = s + (i % 7) + (-i % 5) - (-(i + 1))
end
return s
]])

-- conv_str_tonum: a string used as a number goes through the
-- STRTO path.
add("str_tonum", [[
local s = 0
for i = 1, 200 do
  s = s + tonumber("1.5") + ("2" + 0)
end
return s
]])

-- TNEW / TDUP, and the fold rules keyed on a constant template
-- table (fwd_href_tdup).
add("tnew_tdup", [[
local s = 0
for i = 1, 200 do
  local a = {}
  local b = { 1, 2, 3 }
  local c = { x = 1, y = 2 }
  a[1] = i
  s = s + a[1] + b[2] + c.x + (c.z or 0)
end
return s
]])

-- Allocation sinking with a loop-carried allocation: the PHI
-- paths in lj_opt_sink.c.
add("sink_phi", [[
local p = { x = 0, y = 0 }
for i = 1, 200 do
  p = { x = p.x + i, y = p.y - i }
end
return p.x + p.y
]])

-- Upvalues: UREFO for an open upvalue, UREFC for a closed one,
-- plus the ULOAD/USTORE forwarding around them.
add("upvalues", [[
local acc = 0
local function bump(n) acc = acc + n return acc end
local s = 0
for i = 1, 200 do s = s + bump(i) + acc end
local function make()
  local c = 0
  return function(n) c = c + n return c end
end
local f = make()
for i = 1, 200 do s = s + f(i) end
return s
]])

-- Metatables: FLOAD tab.meta, FREF, and the __index chain.
add("metatable", [[
local base = { get = function(self) return self.v end }
base.__index = base
local s = 0
for i = 1, 200 do
  local o = setmetatable({ v = i }, base)
  s = s + o:get() + (rawget(o, "v") or 0)
end
return s
]])

-- lj_opt_fwd_tab_len: `#t` forwards across stores.
add("tab_len", [[
local t = { 1, 2, 3, 4 }
local s = 0
for i = 1, 200 do
  t[5] = i
  s = s + #t
end
return s
]])

-- FFI: CNEW/CNEWI, cdata constant FLOADs, narrow_cindex and
-- narrow_stripov on 64-bit arithmetic.
add("ffi_array", [[
local ffi = require("ffi")
local a = ffi.new("int[64]")
local s = 0
for i = 0, 60 do a[i] = i end
for k = 1, 200 do
  for i = 0, 59 do s = s + a[i] + a[i + 1] end
end
return s
]])

add("ffi_i64", [[
local ffi = require("ffi")
local s = 0LL
for i = 1, 200 do
  s = s + ffi.cast("int64_t", i) * 3LL - 1LL
end
return tonumber(s)
]])

add("ffi_struct", [==[
local ffi = require("ffi")
pcall(ffi.cdef, "struct irfuzz_pt { double x; double y; int32_t n; }")
local p = ffi.new("struct irfuzz_pt")
local s = 0
for i = 1, 200 do
  p.x = i
  p.y = p.x * 2
  p.n = i
  s = s + p.x + p.y + p.n
end
return s
]==])

-- loop_undo: a type-unstable loop makes lj_opt_loop roll the
-- unroll back instead of emitting PHIs.
add("unstable", [[
local s = 0
local v = 1
for i = 1, 200 do
  s = s + i
  if i == 100 then v = "x" end
  if type(v) == "number" then s = s + v end
end
return s
]])

add("unstable_slot", [[
local t = {}
for i = 1, 200 do t[i] = (i < 100) and i or tostring(i) end
local s = 0
for i = 1, 200 do
  local x = t[i]
  if type(x) == "number" then s = s + x end
end
return s
]])

-- math.* records as FPMATH or a libm CALLN.
add("mathfns", [[
local s = 0.0
for i = 1, 200 do
  s = s + math.floor(i * 1.5) + math.ceil(i * 0.5)
  s = s + math.sqrt(i) + math.abs(-i) + math.max(i, 3) + math.min(i, 3)
  s = s + math.sin(i) + math.exp(i % 5) + math.log(i)
end
return s
]])

-- STRTO: a string where a number is expected reaches
-- lj_opt_narrow_toint / _tobit through the string->number
-- coercion, and a non-numeric one aborts the trace.
add("str_coerce", [[
local bit = require("bit")
local s = "abcdefghij"
local n = 0
for i = 1, 200 do
  n = n + bit.band("5", 255) + bit.tobit("3")
  n = n + #s:sub("2", "4") + ("7" * 1) + ("1.5" + 0.5)
end
return n
]])

-- narrow_mod's FP path: `%` on two non-integral operands is
-- rewritten as rb - floor(rb/rc)*rc rather than narrowed.
add("mod_num", [[
local s = 0.0
for i = 1, 200 do
  local a = i * 1.5
  s = s + (a % 2.5) + (a % -1.25) + ((-a) % 3.5)
end
return s
]])

-- narrow_cindex with a non-integer index: an FFI subscript takes
-- its index through lj_opt_narrow_cindex, which converts a num
-- with IRCONV_ANY instead of narrowing it.
add("ffi_index_num", [[
local ffi = require("ffi")
local a = ffi.new("double[64]")
local s = 0.0
for i = 0, 60 do a[i] = i * 0.5 end
for k = 1, 200 do
  for i = 0, 59 do
    local x = i * 1.0
    s = s + a[x] + a[x + 1.0]
  end
end
return s
]])

-- LJ_TRERR_PHIOV: more loop-carried values than the PHI limit
-- makes lj_opt_loop throw and loop_undo roll the unroll back.
add("phi_overflow", [[
local a1,a2,a3,a4,a5,a6,a7,a8 = 1,2,3,4,5,6,7,8
local b1,b2,b3,b4,b5,b6,b7,b8 = 1,2,3,4,5,6,7,8
local c1,c2,c3,c4,c5,c6,c7,c8 = 1,2,3,4,5,6,7,8
local d1,d2,d3,d4,d5,d6,d7,d8 = 1,2,3,4,5,6,7,8
local e1,e2,e3,e4,e5,e6,e7,e8 = 1,2,3,4,5,6,7,8
for i = 1, 300 do
  a1=a1+i a2=a2+a1 a3=a3+a2 a4=a4+a3 a5=a5+a4 a6=a6+a5 a7=a7+a6 a8=a8+a7
  b1=b1+a8 b2=b2+b1 b3=b3+b2 b4=b4+b3 b5=b5+b4 b6=b6+b5 b7=b7+b6 b8=b8+b7
  c1=c1+b8 c2=c2+c1 c3=c3+c2 c4=c4+c3 c5=c5+c4 c6=c6+c5 c7=c7+c6 c8=c8+c7
  d1=d1+c8 d2=d2+d1 d3=d3+d2 d4=d4+d3 d5=d5+d4 d6=d6+d5 d7=d7+d6 d8=d8+d7
  e1=e1+d8 e2=e2+e1 e3=e3+e2 e4=e4+e3 e5=e5+e4 e6=e6+e5 e7=e7+e6 e8=e8+e7
end
return a1+b1+c1+d1+e1+a8+b8+c8+d8+e8
]])

-- table.clear / table.new are recorded as a CALLS, which
-- fwd_aa_tab_clear has to treat as clobbering the whole table.
add("tab_clear", [[
local ok, tnew = pcall(require, "table.new")
local okc, tclear = pcall(require, "table.clear")
if not (ok and okc) then return 0 end
local s = 0
for i = 1, 200 do
  local t = tnew(4, 0)
  t[1] = i
  s = s + (t[1] or 0) + #t
  tclear(t)
  s = s + (t[1] or 0) + #t
  -- A CALLS that is not a table.clear: the scan has to walk past it.
  local u = tnew(2, 0)
  u[1] = i
  s = s + (u[1] or 0) + #u + (t[1] or 0)
end
return s
]])

-- A constant template table read in a loop: fwd_ahload resolves
-- the element out of the TDUP's own template rather than the IR.
add("tdup_const", [[
local s = 0
for i = 1, 200 do
  local a = { 11, 22, 33 }
  local b = { "x", "yy", "zzz" }
  local c = { p = 1.5, q = 2.5 }
  s = s + a[1] + a[3] + #b[2] + c.p + (c.r and 1 or 0)
end
return s
]])

-- A cdata accumulator carried across the loop: CNEWI under a PHI
-- is what sink_checkphi has to reject.
add("ffi_phi", [[
local ffi = require("ffi")
local acc = ffi.new("int64_t", 0)
local box = ffi.new("struct { int64_t v; }")
for i = 1, 200 do
  acc = acc + i
  box.v = acc
end
return tonumber(acc) + tonumber(box.v)
]])

-- Storing GC values into a table in a loop emits the write
-- barrier (TBAR/OBAR) that dse_ustore and dse_fstore have to see.
add("gcstore", [[
local t = {}
local u = { v = "a" }
local s = 0
for i = 1, 200 do
  local k = tostring(i % 5)
  t[1] = k
  u.v = k
  s = s + #t[1] + #u.v
end
return s
]])

-- Both upvalue kinds in one trace: aa_uref only takes its
-- "different UREFx type" exit when a UREFO and a UREFC meet.
add("upval_mixed", [[
local open1 = 0
local function outer()
  local closed = 0
  local function inner(n)
    open1 = open1 + n
    closed = closed + n
    return open1 + closed
  end
  return inner
end
local f = outer()
local s = 0
for i = 1, 200 do s = s + f(i) + open1 end
return s
]])

-- Nested and side-exiting loops, so lj_opt_loop sees a trace that
-- already contains PHIs and snapshots from an inner one.
add("nested_loops", [[
local s = 0
for i = 1, 60 do
  for j = 1, 60 do
    if (i + j) % 7 == 0 then s = s + i * j else s = s + 1 end
  end
end
return s
]])

-- LJ_TRERR_TYPEINS: a slot whose type differs between loop entry
-- and the back edge makes loop_unroll throw, and lj_opt_loop then
-- calls loop_undo to roll the whole unroll back. A flipped
-- boolean is the case the code comments name.
add("flipflop", [[
local b = false
local s = 0
for i = 1, 300 do
  b = not b
  if b then s = s + i else s = s - 1 end
end
return s
]])

add("typeins_nil", [[
local s = 0.0
local prev
for i = 1, 300 do
  if prev then s = s + prev end
  prev = i * 1.5
end
return s
]])

add("typeins_intnum", [[
local x = 1
local s = 0.0
for i = 1, 300 do
  s = s + x
  x = (i % 2 == 0) and (i * 0.5) or i
end
return s
]])

-- lj_opt_fwd_wasnonnil: before a table store the recorder asks
-- whether the overwritten value could have been nil. Both of its
-- scans need something for the same table already in the trace,
-- so this loads before it stores, stores the same slot twice, and
-- mixes nil stores with constant and with variable keys -- the
-- latter is the only way to make an HREF and an HREFK key meet.
add("wasnonnil", [==[
local t = { 1, 2, 3, 4, 5, 6, 7, 8 }
local h = { a = 1, b = 2, c = 3, d = 4, p = 1, q = 2, r = 3, s = 4 }
local keys = { "p", "q", "r", "s" }
local s = 0
for i = 1, 200 do
  -- Every xref has to exist before the nil stores below: the scan
  -- starts at the newest store and stops at the xref, so a nil
  -- store emitted earlier is never even looked at.
  s = s + t[4] + t[5] + h.b + h.d
  t[5] = i
  t[5] = i + 1
  h.d = i
  h.d = i + 1
  t[8] = nil
  t[4] = i
  t[i % 3 + 1] = nil
  t[4] = i + 1
  h.c = nil
  h.b = i
  local k = keys[i % 4 + 1]
  h[k] = nil
  h.b = i + 1
  h[k] = i
  h.c = i
  s = s + t[4] + h.b
end
return s
]==])

-- lj_opt_dse_fstore: the recorder emits only two FSTOREs,
-- tab.meta from setmetatable and the tab.nomm cache invalidation.
-- Two setmetatable calls on the same table are a MUST alias with
-- a different value; on two tables the recorder cannot
-- disambiguate (neither is an allocation in the trace) they are a
-- MAY alias, and repeating the same metatable makes that MAY
-- carry the same value.
add("setmeta_dse", [[
local m1 = { __index = function() return 1 end }
local m2 = { __index = function() return 2 end }
local a, b = {}, {}
local s = 0
for i = 1, 200 do
  setmetatable(a, m1)
  setmetatable(b, m1)
  setmetatable(a, m2)
  setmetatable(b, m2)
  setmetatable(a, m2)
  s = s + a[1] + b[1]
end
return s
]])

-- lj_opt_dse_ustore: two stores to the same upvalue with nothing
-- in between let the first one be removed. With a GC value the
-- dead store also owns the OBAR that follows it, which is the
-- only way to reach the barrier-removal loop. The n2 pair keeps a
-- guard between the stores instead, which is what blocks the
-- elimination.
--
-- The upvalues have to be *closed*: an open upvalue that still
-- points into the recorded frame is resolved to the stack slot it
-- aliases, and no USTORE is emitted at all. Only a closed one
-- takes the UREFC path -- which is also the only one with a
-- barrier.
add("upval_dse", [[
local function make()
  local n1, n2, g = 0, 0, "a"
  local t = { "x", "yy", "zzz" }
  return function(i)
    n1 = 1
    n1 = i
    g = "b"
    g = "c"
    n2 = i
    local x = t[i % 3 + 1]
    n2 = #x
    return n1 + n2 + #g
  end
end
local f = make()
local s = 0
for i = 1, 200 do s = s + f(i) end
return s
]])

-- aa_uref's last case: two upvalues of two different closures
-- whose disambiguation hashes collide are a MAY alias. The hash
-- is derived from the upvalue's address, so the only way to reach
-- it is to put enough closures in one trace that two of them
-- collide in the low byte, and to store the same value through
-- all of them.
add("upval_hash", [[
local function make()
  local c = 0
  return function(v) c = v return c end
end
local fs = {}
for i = 1, 48 do fs[i] = make() end
local src = { "local fs = ...\nlocal s = 0\nfor i = 1, 200 do\n" }
for i = 1, 48 do
  src[#src + 1] = ("  s = s + fs[%d](7)\n"):format(i)
end
src[#src + 1] = "end\nreturn s\n"
return assert(load(table.concat(src)))(fs)
]])

-- abc_fwd wants ABC(asize, (i+k)+(-k)), which is what t[i-1] next
-- to t[i] leaves behind once the loop is unrolled; abc_invar
-- wants a bounds check on a loop-invariant index, and abc_k two
-- checks on constant indices.
add("abc_shapes", [[
local t = {}
for i = 1, 64 do t[i] = i end
local n = 60
local s = 0
for k = 1, 200 do
  for i = 2, 60 do
    s = s + t[i] + t[i - 1] + t[i + 1] + t[n] + t[3] + t[7]
  end
end
return s
]])

-- loop_emit_phi walks the CARG chain of a call in the variant
-- part whose arguments live in the invariant part. That needs a
-- call the optimizer will not hoist -- one that allocates -- with
-- arguments that are invariant but not constant.
add("invar_call", [[
local cfg = { "ab", 3, 2 }
local x, y, z = cfg[1], cfg[2], cfg[3]
local s = 0
local acc = ""
for i = 1, 200 do
  acc = string.rep(x, y)
  s = s + #acc + #string.sub(x, z, y) + #table.concat(cfg, x, z, y)
end
return s + #acc
]])

-- aa_xref / aa_cnew: two distinct cdata allocations never alias,
-- fields at different offsets of one of them do not overlap, and
-- the same offset read back at another type is punning. A pointer
-- stored into a table escapes, which is what aa_escape reports.
add("ffi_alias", [[
local ffi = require("ffi")
pcall(ffi.cdef, "struct irfuzz_ab { int32_t a; int32_t b; double d; }")
local keep = {}
local s = 0
for i = 1, 200 do
  local p = ffi.new("struct irfuzz_ab")
  local q = ffi.new("struct irfuzz_ab")
  p.a = i
  q.a = -i
  p.b = p.a + 1
  p.d = i * 0.5
  q.d = p.d
  keep[1] = q
  s = s + p.a + p.b + q.a + p.d + keep[1].d
end
return s
]])

-- lj_opt_fwd_hrefk forwards a key lookup from the NEWREF that
-- inserted it, and lj_opt_fwd_href_nokey has to give up once a
-- store may have put the key there. Both need a fresh table per
-- iteration, a key inserted during the trace, and a num key --
-- which can move from the array part to the hash part behind the
-- optimizer's back.
add("newref_fwd", [[
local s = 0
for i = 1, 200 do
  local t = { a = 1, z = 2, [1.5] = 3 }
  local k = i + 0.5
  t.b = i
  t[k] = i
  s = s + t.a + t.b + t[k] + t[1.5]
  s = s + (t[k + 1] or 0) + (t[i .. "x"] or 0)
end
return s
]])

-- lj_opt_fwd_href_nokey gives up when an array store might have
-- moved the key into the hash part. The num key has to be a
-- constant one: a variable num key on a table that has an array
-- part is an NYI abort in the recorder, so the trace would never
-- get here.
add("href_nokey", [[
local s = 0
for i = 1, 200 do
  local t = { 1, 2, 3 }
  t[2] = i
  t[1.5] = i
  s = s + (t[2.5] or 0) + t[1.5] + t[2] + (t.miss and 1 or 0)
end
return s
]])

-- aa_uref's "different UREFx type" exit needs a UREFO and a UREFC
-- in one trace. An open upvalue is only emitted as a UREFO if it
-- does not alias a slot of the recorded frame, so the trace has
-- to start in a loop *below* the function that owns the variable.
add("upval_open", [[
local function mkclosed()
  local c = 0
  return function(n) c = c + n return c end
end
local g = mkclosed()
local function outer()
  local o = 0
  local function inner(n)
    for j = 1, 4 do
      o = o + j
      o = o + g(j)
    end
    return o
  end
  for i = 1, 200 do inner(i) end
  return o
end
return outer()
]])

-- An immutable upvalue holding cdata is constified, so its
-- pointer arithmetic folds to a constant pointer (kfold_add_kgc)
-- and the accesses become base+offset off a KPTR, which is the
-- pair aa_xref normalizes. Passing the same cdata as an argument
-- keeps it a variable instead, and then neither side is an
-- allocation.
add("ffi_kptr", [[
local ffi = require("ffi")
local a = ffi.new("int32_t[8]")
local b = ffi.new("double[8]")
local function via(p, q)
  p[2] = 3
  q[2] = 4.5
  return p[2] + q[2]
end
local s = 0
for i = 1, 200 do
  a[0] = i
  a[1] = i + 1
  b[0] = i * 0.5
  s = s + a[0] + a[1] + b[0] + via(a, b)
end
return s
]])

-- aa_ahref disambiguates t[base+-o1] from t[base+-o2] only when
-- both offsets are there, so the trace needs stores through two
-- shifted indices, not just loads.
add("aref_offsets", [[
local t = {}
for i = 1, 72 do t[i] = i end
local s = 0
for k = 1, 200 do
  for i = 3, 60 do
    t[i + 1] = t[i - 1] + 1
    t[i - 1] = t[i + 1] - 1
    t[i + 2] = t[i] + t[i - 2]
    s = s + t[i] + t[i + 3]
  end
end
return s
]])

-- aa_xref's last resort is aa_cnew, which only gets a say when
-- both sides have the same type and neither is a constant
-- pointer: two cdata pointers passed in as arguments. The same
-- two arrays used directly are constified instead, and then both
-- bases are KPTRs. A volatile cast is the one XLOAD the forwarder
-- must never touch.
add("ffi_xalias", [[
local ffi = require("ffi")
local a = ffi.new("int32_t[8]")
local b = ffi.new("int32_t[8]")
local vp = ffi.cast("volatile int32_t *", a)
local function via(p, q)
  p[0] = 5
  p[2] = 3
  q[2] = p[2] + 1
  return p[0] + p[2] + q[2]
end
local s = 0
for i = 1, 200 do
  a[0] = i
  a[1] = i + 1
  b[0] = a[0] + a[1]
  b[1] = b[0]
  s = s + a[0] + a[1] + b[0] + b[1] + vp[0] + via(a, b)
end
return s
]])

-- The rules keyed on a *constant* GC object. An upvalue that is
-- never assigned is constified, so the cdata and the strings
-- below reach the fold engine as KGCs: pointer arithmetic on one
-- folds to a constant pointer (kfold_add_kgc) whose loads are
-- then done at compile time (kfold_xload, xload_kptr, the cdata
-- FLOADs). The string half covers the SNEW rules: a freshly built
-- string compared against a constant one, and its length.
add("const_gc", [[
local ffi = require("ffi")
local arr = ffi.new("int32_t[8]")
local ptr = ffi.cast("int32_t *", arr)
local box = ffi.new("int64_t[1]")
local txt = "abcdef"
local bad = "not a number"
local function touch(i, a, b)
  arr[0] = i
  arr[1] = i + 1
  box[0] = i
  local s = a .. b
  local n = #s + #txt + (tonumber(bad) and 1 or 0)
  if s == "xy" then n = n + 1 end
  if s ~= "zz" then n = n + 2 end
  return n + arr[0] + arr[1] + ptr[0] + tonumber(box[0])
end
local s = 0
for i = 1, 200 do s = s + touch(i, "x", "y") end
return s
]])

-- kfold_xload folds a load from a constant pointer at compile
-- time, one case per width. A cdata upvalue that is only ever
-- read is constified, its element address folds to a KKPTR, and
-- the load then disappears -- but only if nothing in the trace
-- stores to it, so these arrays are filled before the loop and
-- never written.
add("cdata_ro", [[
local ffi = require("ffi")
local d = ffi.new("double[2]", 1.5, 2.5)
local q = ffi.new("int64_t[2]", 7, 8)
local b = ffi.new("uint8_t[4]", 1, 2, 3, 4)
local w = ffi.new("int16_t[2]", -300, 300)
local u = ffi.new("uint16_t[2]", 65000, 1)
local i = ffi.new("int32_t[2]", -5, 5)
local z = ffi.new("complex", 1.5, 2.5)
local function rd(k)
  return d[0] + d[1] + tonumber(q[0]) + tonumber(q[1])
    + b[0] + b[3] + w[0] + w[1] + u[0] + u[1] + i[0] + i[1]
    + z.re + z.im + k
end
local s = 0.0
for k = 1, 200 do s = s + rd(k) end
return s
]])

-- merge_eqne_snew_kgc rewrites a comparison of a freshly built
-- string against a constant one into a length check plus a load
-- of the constant's bytes -- a different load width per length,
-- and no load at all for the empty string.
add("snew_cmp", [[
local s = 0
local parts = { "", "x", "xy", "xyz", "xyzw", "xyzwv" }
for i = 1, 200 do
  local a = parts[i % 6 + 1] .. ""
  if a == "" then s = s + 1 end
  if a == "x" then s = s + 2 end
  if a == "xy" then s = s + 3 end
  if a == "xyz" then s = s + 4 end
  if a == "xyzw" then s = s + 5 end
  if a ~= "q" then s = s + 6 end
  if a ~= "xyzwv" then s = s + 7 end
  s = s + #a
end
return s
]])

-- The other half: if the recorder cannot prove the loop's range
-- up front it keeps a bounds check per access, and the unroll
-- then turns t[i - 1] into t[(i + 1) - 1] -- the shape abc_fwd
-- forwards. A stop value past the end of the array does that; the
-- loop leaves through the break instead.
add("abc_unprovable", [[
local t = {}
for i = 1, 72 do t[i] = i end
local s = 0
for k = 1, 200 do
  for i = 2, 300 do
    if i > 60 then break end
    s = s + t[i] + t[i - 1] + t[i + 1]
    t[i] = t[i - 1] + 1
  end
end
return s
]])

-- abc_fwd only sees a bounds check on an ADD if the index is
-- *not* the loop variable: for a real loop variable the recorder
-- proves the range up front and hoists one invariant check
-- instead. A loop-carried counter that is clamped by hand keeps
-- the per-access checks, and the unroll then turns t[j - 1] into
-- t[(j + 1) - 1].
add("abc_phi", [[
local t = {}
for i = 1, 72 do t[i] = i end
local j = 2
local s = 0
for k = 1, 400 do
  s = s + t[j] + t[j - 1] + t[j + 1]
  t[j] = t[j - 1] + 1
  j = j + 1
  if j > 60 then j = 2 end
end
return s
]])

-- The narrowing error paths: a value that is neither a number nor
-- a numeric string still reaches lj_opt_narrow_toint / _tobit /
-- conv_str_tonum during recording, because the recorder runs
-- before the interpreter throws. Each one aborts the trace, so
-- the calls are wrapped -- the abort is the point.
add("narrow_badtype", [[
local bit = require("bit")
local n = 0
for i = 1, 300 do
  pcall(function() n = n + bit.band(true, 1) end)
  pcall(function() n = n + ("x"):sub(true) end)
  pcall(function() n = n + #("a"):rep(true) end)
  pcall(function() n = n + ("bad" + 1) end)
  pcall(function() n = n + bit.band("bad", 1) end)
  n = n + bit.band(i, 255)
end
return n
]])

-- A Lua call and a multiple-return inside the loop body, so the
-- unroller has a call frame and a result pair to substitute --
-- neither of which a builtin call in the body produces.
add("loop_call_ret", [[
local function add1(x) return x + 1 end
local function pair(x) return x + 1, x - 1 end
local s = 0
for i = 1, 200 do
  s = add1(s)
  local a, b = pair(i)
  s = s + a - b
end
return s
]])

-- A trace that *returns* out of the function it started in: the
-- inner loop goes hot first, so the recorder leaves a frame it
-- never recorded entering and emits RETF.
add("retf_loop", [[
local function inner(x)
  local s = 0
  for i = 1, 4 do s = s + x + i end
  return s
end
local t = 0
for i = 1, 300 do t = t + inner(i) end
return t
]])

-- rec_varg is the only place that sets IRSLOAD_FRAME, and only on
-- its "unknown number of varargs" arm -- so the loop has to sit
-- *inside* the vararg function, where the count is not recorded.
add("varg_loop", [[
local function varg(...)
  local s = 0
  for i = 1, 200 do
    local a, b = ...
    s = s + a + b + select("#", ...)
  end
  return s
end
return varg(3, 4)
]])

-- lj_opt_narrow_unm's integer path leaves the two constants it
-- cannot negate (0 and INT_MIN) to a plain CONV, and
-- lj_opt_narrow_forl declines a loop whose index can overflow.
add("narrow_edge", [[
local bit = require("bit")
local s = 0.0
for i = 1, 200 do
  local z = bit.band(i, 0)
  local m = bit.tobit(0x80000000)
  s = s + (-z) + (-m) + (-bit.band(i, 3))
end
for i = 2147483000, 2147483647 do
  s = s + 1
  if i > 2147483010 then break end
end
for i = 1, 4e9, 1e9 do s = s + 1 end
return s
]])

-- narrow_stripov_backprop backtracks when its instruction stack
-- runs out, which needs a wide *tree* of overflow-checked adds
-- under a bit operation -- a linear chain hits the depth limit
-- first. The leaves are distinct so CSE cannot collapse them.
add("stripov_deep", [[
local bit = require("bit")
local function tree(lo, hi)
  if lo == hi then return ("(x + %d)"):format(lo) end
  local mid = math.floor((lo + hi) / 2)
  return "(" .. tree(lo, mid) .. " + " .. tree(mid + 1, hi) .. ")"
end
local src = "local bit = ...\nlocal s = 0\nfor i = 1, 200 do\n"
  .. "  local x = bit.band(i, 255)\n"
  .. "  s = s + bit.band(" .. tree(1, 400) .. ", 255)\n"
  .. "end\nreturn s\n"
return assert(load(src))(bit)
]])

-- The rest of lj_opt_sink's PHI logic: a sunken allocation whose
-- fields are a constant, an integer PHI that is stored as a
-- number (the CONV case), and two allocations that reference each
-- other, which is what makes the re-marking loop iterate.
add("sink_phi2", [[
local bit = require("bit")
local p = { x = 0.0, n = 0, k = 1 }
local q = { v = 0.0, o = p }
for i = 1, 300 do
  p = { x = p.x + i, n = bit.band(p.n + i, 255), k = 1 }
  q = { v = q.v + p.x, o = p }
end
return p.x + p.n + p.k + q.v + q.o.n
]])

-- A CNEWI carried across the loop whose new value comes from a
-- load rather than from the PHI itself: sink_checkphi rejects it,
-- and the allocation stays.
add("sink_cnewi", [[
local ffi = require("ffi")
local src = ffi.new("int64_t[4]", 1, 2, 3, 4)
local acc = ffi.new("int64_t", 0)
for i = 1, 300 do
  acc = acc + src[i % 4]
  acc = acc * 1LL + src[(i + 1) % 4]
end
return tonumber(acc)
]])

-- loop_undo has to drop the narrowing backpropagation cache, so
-- the type-unstable loop below narrows as well as flips a type,
-- and the long body makes the unroll itself run out of trace
-- space.
add("loop_undo_bp", [[
local bit = require("bit")
local v = 1
local s = 0
for i = 1, 300 do
  local a = bit.band(i, 255) + 1
  local b = bit.bxor(a, 3) + 2
  s = s + a + b + (i % 7)
  if i == 150 then v = "x" end
  if type(v) == "number" then s = s + v end
end
return s
]])

-- loop_emit_phi walks the CARG chain of a call whose arguments
-- are all loop-invariant: the unroll CSEs the chain back to the
-- first copy while the call itself, having side effects, is
-- re-emitted. table.new is that call, as long as its arguments
-- are variables -- constant ones are skipped by the walk.
add("invar_carg", [[
local ok, tnew = pcall(require, "table.new")
if not ok then return 0 end
local cfg = { 4, 2 }
local a, b = cfg[1], cfg[2]
local s = 0
for i = 1, 200 do
  local t = tnew(a, b)
  t[1] = i
  s = s + (t[1] or 0) + #t
end
return s
]])

-- A loop body with no guard at all lets loop_unroll drop the
-- snapshot it took for the back edge.
add("loop_noguard", [[
local s = 0.0
local x = 1.5
for i = 1, 200 do
  s = s + x * 2.0 - 0.25
end
return s
]])

-- sink_checkphi's constant arm: a loop-carried cdata that is
-- sometimes assigned a constant, so the PHI's other side is a
-- constant reference rather than an instruction.
add("sink_const", [[
local ffi = require("ffi")
local acc = ffi.new("int64_t", 0)
local s = 0
for i = 1, 300 do
  if i % 4 == 0 then acc = ffi.new("int64_t", 5) else acc = acc + 1 end
  s = s + i
end
return s + tonumber(acc)
]])

-- The PHI limit is reached from three different places: the plain
-- loop-carried value, the num <- int conversion path, and the
-- slots loop_emit_phi has to add PHIs for on its own. Integer
-- accumulators that are also read as numbers cover the second,
-- and values that only ever live in locals cover the third.
add("phi_overflow_conv", [[
local bit = require("bit")
local src = { "local bit = ...\n" }
for k = 1, 40 do
  src[#src + 1] = ("local x%d = %d\n"):format(k, k)
end
src[#src + 1] = "local s = 0.0\nfor i = 1, 300 do\n"
for k = 1, 40 do
  src[#src + 1] = ("  x%d = bit.band(x%d + i, 255)\n"):format(k, k)
  src[#src + 1] = ("  s = s + x%d * 0.5\n"):format(k)
end
src[#src + 1] = "end\nreturn s\n"
return assert(load(table.concat(src)))(bit)
]])

-- sink_remark_phi iterates only when two sunken allocations
-- disagree about being sunk, which needs them to reference each
-- other across the back edge.
add("sink_cycle", [[
local p = { v = 1.0, o = false }
local q = { v = 2.0, o = false }
local s = 0.0
for i = 1, 300 do
  local np = { v = q.v + i, o = q }
  local nq = { v = p.v - i, o = p }
  p, q = np, nq
  s = s + p.v + q.v
end
return s + p.v + q.v
]])

-- kfold_xload has one arm per load width, and the only constant
-- pointers the recorder interns point into a cdata whose ctype is
-- a number, a pointer, a complex or a *vector* -- a struct or
-- array stays mutable. Vectors are therefore the only way to fold
-- a compile-time load of an 8-, 16- or 64-bit element, and a
-- scalar cdata covers the 32-bit field load.
add("cdata_vector", [[
local ffi = require("ffi")
local v8 = ffi.new("uint8_t __attribute__((vector_size(8)))")
local v16 = ffi.new("int16_t __attribute__((vector_size(8)))")
local v64 = ffi.new("int64_t __attribute__((vector_size(16)))")
local i32 = ffi.new("int32_t", 7)
local i64 = ffi.new("int64_t", 9)
local function rd(k)
  return v8[1] + v8[7] + v16[1] + v16[3]
    + tonumber(v64[0]) + tonumber(v64[1])
    + tonumber(i32) + tonumber(i64) + k
end
local s = 0
for i = 1, 200 do s = s + rd(i) end
return s
]])

-- fwd_aa_tab_clear has to walk past a table.clear it can prove
-- does not alias, which needs two of them in one trace -- one on
-- a table allocated in the trace, one on a table from outside it.
add("tab_clear2", [[
local ok, tclear = pcall(require, "table.clear")
if not ok then return 0 end
local u = {}
local s = 0
for i = 1, 200 do
  local t = {}
  t[1] = i
  u[1] = i
  tclear(t)
  tclear(u)
  s = s + (t[1] or 0) + (u[1] or 0) + #t + #u
end
return s
]])

-- loop_unroll drops the final snapshot when no guard was emitted
-- after the last one it substituted. That needs an unconditional
-- back-edge, so the loop test is not the last guard, and an
-- FP-only tail: an int counter's ADDOV is a guard and re-arms
-- J->guardemit.
add("loop_snap_drop", [[
local s = 0.0
local i = 0.0
while true do
  if i >= 200.0 then break end
  i = i + 1.0
  s = s + i * 0.75
end
return s
]])

return { chunks = chunks }
