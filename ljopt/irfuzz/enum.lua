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
local IRT_NUM, IRT_INT = gen.IRT_NUM, gen.IRT_INT

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
}

-- The leaf operand universe for a type: `ninputs` SLOAD refs
-- (1-based stream indices) followed by the fold-rule constants.
local function leaves_for(t, ninputs)
  local out = {}
  for i = 1, ninputs do
    out[#out + 1] = { k = K.REF, v = i, txt = ("%04d"):format(i) }
  end
  local consts = (t == IRT_NUM) and gen.NUM_CONSTS or gen.INT_CONSTS
  local ck = (t == IRT_NUM) and K.KNUM or K.KINT
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

  -- Fixed prologue: the typed SLOAD inputs. Body refs follow.
  local prologue = {}
  for slot = 1, ninputs do
    prologue[slot] = { op = gen.op_num("SLOAD"), t = t,
      ak = K.LIT, av = slot, bk = K.LIT, bv = gen.SLOAD_TYPECHECK }
  end

  local body = {}   -- current chain being built (partial insns)

  -- Recursively fill body[level]; at level > depth, yield the trace.
  local function rec(level, prev)
    if level > depth then
      local insns = {}
      for _, x in ipairs(prologue) do insns[#insns + 1] = x end
      for _, x in ipairs(body) do insns[#insns + 1] = x end
      coroutine.yield({ insns = insns, outputs = gen.roots(insns) })
      return
    end
    local this_ref = ninputs + level
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

return {
  iter = iter,
  count = count,
  leaves_for = leaves_for,
  OPS = OPS,
}
