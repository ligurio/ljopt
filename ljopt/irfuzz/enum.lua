-- Exhaustive (deterministic, seedless) enumeration of short
-- arithmetic IR traces for the ljopt fuzzer.
--
-- Where gen.lua *samples* random traces, enum.lua *walks the full
-- cross product* of (op, operands) for a bounded leaf set and a
-- fixed depth, so every constant-triggered and multi-level
-- arithmetic fold in the chosen space is exercised at least once.
--
-- Shape: a linear CHAIN of `depth` ops. Each op consumes the
-- previous result, so only the last op is a root (compared), and
-- the intermediates are dead -- exactly the a=b+c; d=a+c; e=d+d
-- structure. This is the shape that builds fold-rule depth:
--
--   v1 = op1(leaf, leaf)      -- level 1: two leaves
--   v2 = op2(v1,   leaf)      -- level 2: consume v1, one leaf
--   v3 = op3(v2,   leaf)      -- level 3 (root)
--
-- A "leaf" is an SLOAD input or one of the fold-rule constants
-- (gen.NUM_CONSTS / gen.INT_CONSTS). For non-commutative ops
-- (SUB/DIV/shifts) BOTH operand orders (prev,leaf) and (leaf,prev)
-- are emitted at levels > 1.
--
-- Feasibility: the space is |ops|^depth * |leaves|^(depth+1) and
-- explodes fast (a num depth-3 chain with 1 input + 11 consts + 6
-- binary ops is 6^3 * 12^4 ~= 4.5M). The leaf set, op set and depth
-- are the knobs that keep a run tractable; `count()` reports the
-- total up front and enumerate() is a lazy iterator so a driver can
-- bound it with a limit.

local gen = require("ljopt.irfuzz.gen")

local K = gen.kinds
local IRT_NUM, IRT_INT, IRT_I64 = gen.IRT_NUM, gen.IRT_INT, gen.IRT_I64

-- Per-type op descriptors. `arity` is the number of *value*
-- operands. Special forms mirror gen.lua's emit handling:
--   mirror   -- unary op that carries op2 = op1 (NEG/ABS, and the
--               SSE sign-mask convention LuaJIT's crecord uses).
--   no_op2   -- unary op with no op2 at all (BNOT/BSWAP).
--   lits     -- unary value + an op2 LIT enumerated from this list
--               (FPMATH rounding modes).
--   rlits    -- binary where op2 is not a leaf but a constant from
--               this list, of kind rlit_kind (LDEXP exponent).
-- Excluded ops match gen's blacklist: POW / num MOD / int DIV,MOD
-- (recorder-impossible or ljopt gap) and BROL/BROR (SMT-preamble
-- gap). Callers hunting gaps can pass their own op list.
local OPS = {
  [IRT_NUM] = {
    { name = "ADD", arity = 2, commut = true },
    { name = "SUB", arity = 2 },
    { name = "MUL", arity = 2, commut = true },
    { name = "DIV", arity = 2 },
    { name = "MIN", arity = 2, commut = true },
    { name = "MAX", arity = 2, commut = true },
    { name = "NEG", arity = 1, mirror = true },
    { name = "ABS", arity = 1, mirror = true },
    { name = "FPMATH", arity = 1, lits = gen.FPMATH_MODES },
    { name = "LDEXP", arity = 2, rlits = gen.LDEXP_EXPS,
      rlit_kind = K.KNUM },
  },
  [IRT_INT] = {
    { name = "ADD", arity = 2, commut = true },
    { name = "SUB", arity = 2 },
    { name = "MUL", arity = 2, commut = true },
    { name = "BAND", arity = 2, commut = true },
    { name = "BOR", arity = 2, commut = true },
    { name = "BXOR", arity = 2, commut = true },
    { name = "BSHL", arity = 2 },
    { name = "BSHR", arity = 2 },
    { name = "BSAR", arity = 2 },
    { name = "NEG", arity = 1, mirror = true },
    { name = "BNOT", arity = 1, no_op2 = true },
    { name = "BSWAP", arity = 1, no_op2 = true },
  },
  -- i64: inputs are int SLOADs widened via CONV int->i64 (see
  -- prologue_for); constants are KINT64. Only ops ljopt models for
  -- i64 AND the recorder emits via FFI 64-bit arithmetic/bitwise:
  -- ADD/SUB/MUL/BAND/BOR/BXOR. Excluded: DIV/MOD (recorder lowers
  -- 64-bit div/mod to CALL helpers, no IR_DIV), NEG/BSWAP (no ljopt
  -- I64 translator), shifts (same count-mask gap as int shifts,
  -- needs separate verification first).
  [IRT_I64] = {
    { name = "ADD", arity = 2, commut = true },
    { name = "SUB", arity = 2 },
    { name = "MUL", arity = 2, commut = true },
    { name = "BAND", arity = 2, commut = true },
    { name = "BOR", arity = 2, commut = true },
    { name = "BXOR", arity = 2, commut = true },
  },
}

-- The leaf operand universe for a type: `ninputs` SLOAD refs
-- (1-based stream indices) followed by the fold-rule constants.
-- The fixed prologue that sources `ninputs` typed input values,
-- plus the stream refs those values live at. num/int read a Lua
-- stack slot directly (SLOAD); i64 has no direct stack form, so it
-- reads an int SLOAD and widens it with CONV int->i64 SEXT -- the
-- recorder's own way to get an i64 from a Lua number
-- (lj_opt_narrow.c). Returns (insns, input_refs).
local function prologue_for(t, ninputs)
  local insns, input_refs = {}, {}
  if t == IRT_I64 then
    for slot = 1, ninputs do
      insns[#insns + 1] = { op = gen.op_num("SLOAD"), t = IRT_INT,
        ak = K.LIT, av = slot, bk = K.LIT, bv = gen.SLOAD_TYPECHECK }
    end
    for slot = 1, ninputs do
      insns[#insns + 1] = { op = gen.op_num("CONV"), t = IRT_I64,
        ak = K.REF, av = slot, bk = K.LIT, bv = gen.CONV_I64_INT_SEXT }
      input_refs[#input_refs + 1] = ninputs + slot  -- the CONV result
    end
  else
    for slot = 1, ninputs do
      insns[#insns + 1] = { op = gen.op_num("SLOAD"), t = t,
        ak = K.LIT, av = slot, bk = K.LIT, bv = gen.SLOAD_TYPECHECK }
      input_refs[#input_refs + 1] = slot
    end
  end
  return insns, input_refs
end

-- The leaf operand universe for a type: the input value refs (from
-- prologue_for) followed by the fold-rule constants of that type.
local function leaves_for(t, ninputs)
  local _, input_refs = prologue_for(t, ninputs)
  local out = {}
  for _, r in ipairs(input_refs) do
    out[#out + 1] = { k = K.REF, v = r, txt = ("%04d"):format(r) }
  end
  local consts, ck
  if t == IRT_NUM then consts, ck = gen.NUM_CONSTS, K.KNUM
  elseif t == IRT_I64 then consts, ck = gen.I64_CONSTS, K.KINT64
  else consts, ck = gen.INT_CONSTS, K.KINT end
  for _, c in ipairs(consts) do
    out[#out + 1] = { k = ck, v = c, txt = tostring(c) }
  end
  return out
end

-- All (op-descriptor, insn-tail) applications at a position, given
-- the value operand(s) available. `val` is the single value operand
-- for a chain step (prev ref at level > 1); at level 1 both operands
-- come from the leaf set so `val` is nil and `left`/`right` iterate.
-- Yields a partial insn {op,t,ak,av,bk,bv} (without the stream slot,
-- which the caller assigns) via callback `emit`.
local function each_application(t, leaves, op, level, prev, emit)
  local opnum = gen.op_num(op.name)
  local function ins(ak, av, bk, bv)
    emit({ op = opnum, t = t, ak = ak, av = av, bk = bk, bv = bv })
  end

  if op.arity == 1 then
    -- Unary: operand is a leaf at level 1, else the previous ref.
    local operands = level == 1 and leaves or { prev }
    for _, x in ipairs(operands) do
      if op.lits then
        for _, m in ipairs(op.lits) do ins(x.k, x.v, K.LIT, m) end
      elseif op.no_op2 then
        ins(x.k, x.v, K.NONE, 0)
      else -- mirror
        ins(x.k, x.v, x.k, x.v)
      end
    end
    return
  end

  -- Binary. LDEXP's second operand is an exponent constant, not a
  -- leaf.
  if op.rlits then
    local operands = level == 1 and leaves or { prev }
    for _, x in ipairs(operands) do
      for _, e in ipairs(op.rlits) do ins(x.k, x.v, op.rlit_kind, e) end
    end
    return
  end

  if level == 1 then
    for _, a in ipairs(leaves) do
      for _, b in ipairs(leaves) do ins(a.k, a.v, b.k, b.v) end
    end
  else
    -- Chain step: prev is one operand, a leaf the other. Emit
    -- (prev, leaf); for non-commutative ops also (leaf, prev).
    for _, x in ipairs(leaves) do
      ins(prev.k, prev.v, x.k, x.v)
      if not op.commut then ins(x.k, x.v, prev.k, prev.v) end
    end
  end
end

-- Lazily enumerate every chain trace for one type as a coroutine
-- yielding { insns = <list>, outputs = <root refs> }.
--
-- opts: { type = IRT_NUM|IRT_INT (default NUM), depth = 3,
--         ninputs = 1, ops = <descriptor list> }
local function iter(opts)
  opts = opts or {}
  local t = opts.type or IRT_NUM
  local depth = opts.depth or 3
  local ninputs = opts.ninputs or 1
  local ops = opts.ops or OPS[t]
  local leaves = leaves_for(t, ninputs)

  -- Fixed prologue (SLOADs, plus CONVs for i64); body refs follow.
  local prologue = prologue_for(t, ninputs)
  local nprologue = #prologue

  local body = {}   -- current chain being built (partial insns)

  -- Recursively fill body[level]; at level > depth, yield the trace.
  local function rec(level, prev)
    if level > depth then
      local insns = {}
      for _, x in ipairs(prologue) do insns[#insns + 1] = x end
      for _, x in ipairs(body) do insns[#insns + 1] = x end
      -- Strict linear chain: the sole observable value is the last
      -- op (level `depth`). Using it directly rather than roots()
      -- keeps a dead input source (e.g. an unused i64 CONV) from
      -- being compared as a spurious extra output.
      coroutine.yield({ insns = insns, outputs = { nprologue + depth } })
      return
    end
    local this_ref = nprologue + level
    for _, op in ipairs(ops) do
      each_application(t, leaves, op, level, prev, function(insn)
        body[level] = insn
        rec(level + 1, { k = K.REF, v = this_ref })
      end)
    end
    body[level] = nil
  end

  return coroutine.wrap(function() rec(1, nil) end)
end

-- Count the traces iter(opts) would yield, without building them.
-- Cheap closed form per level, so a driver can print the total and
-- decide a limit before committing to a run.
local function count(opts)
  opts = opts or {}
  local t = opts.type or IRT_NUM
  local depth = opts.depth or 3
  local ninputs = opts.ninputs or 1
  local ops = opts.ops or OPS[t]
  local nleaf = #leaves_for(t, ninputs)

  local function apps(op, level)
    if op.arity == 1 then
      local base = level == 1 and nleaf or 1
      return base * (op.lits and #op.lits or 1)
    end
    if op.rlits then
      local base = level == 1 and nleaf or 1
      return base * #op.rlits
    end
    if level == 1 then return nleaf * nleaf end
    return nleaf * (op.commut and 1 or 2)
  end

  local total = 1
  for level = 1, depth do
    local per_level = 0
    for _, op in ipairs(ops) do per_level = per_level + apps(op, level) end
    total = total * per_level
  end
  return total
end

-- ==========================================================
-- Mixed-type CONV enumeration.
--
-- Where iter() builds single-type chains, iter_mixed() lets the
-- running value change TYPE via CONV body ops, so the CONV fold
-- rules (47 of them in lj_opt_fold.c, otherwise never exercised)
-- fire. A chain starts as an int SLOAD; each step is either an
-- arithmetic op combining the running value with a same-type
-- constant, or a CONV to another modeled type. The value's type
-- at each point determines the legal ops, constants and CONVs.
--
-- Only recorder-faithful CONV modes are emitted (int->i64 is
-- sign-extended as the recorder does it, num->int uses IRCONV_ANY,
-- etc.). Types are limited to the ones ljopt fully models
-- (int/i64/num); u32/u64/narrow/flt are added once ljopt learns
-- them.

local IRT_FLT = 13

-- Arithmetic op menus per type (same faithful sets as OPS above).
-- flt has NONE: LuaJIT does float32 arithmetic in double and only
-- rounds at CONV boundaries, so flt appears solely as a CONV
-- endpoint (num<->flt).
local MIXED_ARITH = {
  [IRT_INT] = OPS[IRT_INT],
  [IRT_I64] = OPS[IRT_I64],
  [IRT_NUM] = {
    { name = "ADD", commut = true }, { name = "SUB" },
    { name = "MUL", commut = true }, { name = "DIV" },
    { name = "MIN", commut = true }, { name = "MAX", commut = true },
  },
  [IRT_FLT] = {},
}

-- Per-type constant set + operand kind.
local MIXED_CONST = {
  [IRT_INT] = { consts = gen.INT_CONSTS, kind = K.KINT },
  [IRT_I64] = { consts = gen.I64_CONSTS, kind = K.KINT64 },
  [IRT_NUM] = { consts = gen.NUM_CONSTS, kind = K.KNUM },
}

-- CONV transitions: from-type -> list of { to = type, mode = op2 }.
-- Mode = (dst<<IRCONV_DSH)|src [|IRCONV_SEXT for signed widen]
-- [|IRCONV_ANY for num->int]. IRCONV_DSH=5, SEXT=0x800, ANY=0x1000.
local SEXT, ANY = 0x800, 0x1000
local function cmode(dst, src, extra)
  return dst * 32 + src + (extra or 0)
end
local MIXED_CONV = {
  [IRT_INT] = {
    { to = IRT_I64, mode = cmode(IRT_I64, IRT_INT, SEXT) },
    { to = IRT_NUM, mode = cmode(IRT_NUM, IRT_INT) },
  },
  [IRT_I64] = {
    { to = IRT_INT, mode = cmode(IRT_INT, IRT_I64) },
    { to = IRT_NUM, mode = cmode(IRT_NUM, IRT_I64) },
  },
  [IRT_NUM] = {
    { to = IRT_INT, mode = cmode(IRT_INT, IRT_NUM, ANY) },
    { to = IRT_I64, mode = cmode(IRT_I64, IRT_NUM, ANY) },
    { to = IRT_FLT, mode = cmode(IRT_FLT, IRT_NUM) },  -- round to float32
  },
  [IRT_FLT] = {
    { to = IRT_NUM, mode = cmode(IRT_NUM, IRT_FLT) },  -- widen to double
  },
}

-- Enumerate every mixed-type chain of `depth` steps starting from a
-- single int SLOAD. opts: { depth = 3 }. Yields
-- { insns, outputs } like iter().
local function iter_mixed(opts)
  opts = opts or {}
  local depth = opts.depth or 3
  local body = {}
  local prologue = { { op = gen.op_num("SLOAD"), t = IRT_INT,
    ak = K.LIT, av = 1, bk = K.LIT, bv = gen.SLOAD_TYPECHECK } }

  local function rec(level, cur_type, prev_ref)
    if level > depth then
      local insns = {}
      for _, x in ipairs(prologue) do insns[#insns + 1] = x end
      for _, x in ipairs(body) do insns[#insns + 1] = x end
      coroutine.yield({ insns = insns, outputs = { #insns } })
      return
    end
    local this_ref = 1 + level  -- prologue is 1 insn (SLOAD)
    -- (a) arithmetic op with a same-type constant.
    local cinfo = MIXED_CONST[cur_type]
    for _, op in ipairs(MIXED_ARITH[cur_type]) do
      local opnum = gen.op_num(op.name)
      for _, c in ipairs(cinfo.consts) do
        body[level] = { op = opnum, t = cur_type,
          ak = K.REF, av = prev_ref, bk = cinfo.kind, bv = c }
        rec(level + 1, cur_type, this_ref)
        if not op.commut then
          body[level] = { op = opnum, t = cur_type,
            ak = cinfo.kind, av = c, bk = K.REF, bv = prev_ref }
          rec(level + 1, cur_type, this_ref)
        end
      end
    end
    -- (b) CONV to another modeled type.
    for _, tr in ipairs(MIXED_CONV[cur_type]) do
      body[level] = { op = gen.op_num("CONV"), t = tr.to,
        ak = K.REF, av = prev_ref, bk = K.LIT, bv = tr.mode }
      rec(level + 1, tr.to, this_ref)
    end
    body[level] = nil
  end

  return coroutine.wrap(function() rec(1, IRT_INT, 1) end)
end

-- Count iter_mixed(opts) via DP over (level, type): completions
-- from a state = sum over each choice of completions after it.
local function count_mixed(opts)
  opts = opts or {}
  local depth = opts.depth or 3
  local memo = {}
  local function f(level, t)
    if level > depth then return 1 end
    local key = level * 100 + t
    if memo[key] then return memo[key] end
    local n = 0
    local ci = MIXED_CONST[t]
    local nconst = ci and #ci.consts or 0
    for _, op in ipairs(MIXED_ARITH[t]) do
      n = n + nconst * (op.commut and 1 or 2) * f(level + 1, t)
    end
    for _, tr in ipairs(MIXED_CONV[t]) do
      n = n + f(level + 1, tr.to)
    end
    memo[key] = n
    return n
  end
  return f(1, IRT_INT)
end

return {
  iter = iter,
  count = count,
  iter_mixed = iter_mixed,
  count_mixed = count_mixed,
  leaves_for = leaves_for,
  OPS = OPS,
}
