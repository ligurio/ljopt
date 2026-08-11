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
-- (SUB/DIV/shifts) BOTH operand orders (prev,leaf) and
-- (leaf,prev) are emitted at levels > 1.
--
-- Feasibility: the space is |ops|^depth * |leaves|^(depth+1) and
-- explodes fast (a num depth-3 chain with 1 input + 11 consts + 6
-- binary ops is 6^3 * 12^4 ~= 4.5M). The leaf set, op set and
-- depth are the knobs that keep a run tractable; `count()`
-- reports the total up front and enumerate() is a lazy iterator
-- so a driver can bound it with a limit.

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
-- (recorder-impossible or ljopt gap). Callers hunting gaps can
-- pass their own op list.
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
    -- bit.rol / bit.ror. Counts are masked & 31 by both x86 and
    -- LuaJIT's lj_rol/lj_ror, and by ext_rotate_left/_right.
    { name = "BROL", arity = 2 },
    { name = "BROR", arity = 2 },
    -- Overflow-checked integer arithmetic, emitted by
    -- lj_opt_narrow for Lua-level `+`/`-`/`*` that stayed
    -- integer. Guards: the overflow test is the trace exit.
    { name = "ADDOV", arity = 2, commut = true, guard = true },
    { name = "SUBOV", arity = 2, guard = true },
    { name = "MULOV", arity = 2, commut = true, guard = true },
    -- math.min/max over two integers: recff_math_minmax emits the
    -- op at IRT_INT when neither operand needed a CONV to num.
    { name = "MIN", arity = 2, commut = true },
    { name = "MAX", arity = 2, commut = true },
    -- Lua `%` on two integers: lj_opt_narrow_mod emits IRTI MOD,
    -- but only after guarding the divisor non-zero, so a zero
    -- right operand is recorder-impossible (and folds via idiv).
    { name = "MOD", arity = 2, no_zero_right = true },
    { name = "NEG", arity = 1, mirror = true },
    { name = "BNOT", arity = 1, no_op2 = true },
    { name = "BSWAP", arity = 1, no_op2 = true },
  },
  -- i64: inputs are int SLOADs widened via CONV int->i64 (see
  -- prologue_for); constants are KINT64. Only ops ljopt models
  -- for i64 AND the recorder emits via FFI 64-bit
  -- arithmetic/bitwise: ADD/SUB/MUL/BAND/BOR/BXOR plus the
  -- shifts. Shifts run through BinOpShiftI64 (count masked & 63,
  -- full 64-bit width) -- the i64 sibling of the int shift-mask
  -- fix. Excluded: DIV/MOD (recorder lowers 64-bit div/mod to
  -- CALL helpers, no IR_DIV), NEG/BSWAP (no ljopt I64
  -- translator).
  [IRT_I64] = {
    { name = "ADD", arity = 2, commut = true },
    { name = "SUB", arity = 2 },
    { name = "MUL", arity = 2, commut = true },
    { name = "BAND", arity = 2, commut = true },
    { name = "BOR", arity = 2, commut = true },
    { name = "BXOR", arity = 2, commut = true },
    { name = "BSHL", arity = 2, rlits = gen.SHIFT_COUNTS,
      rlit_kind = K.KINT },
    { name = "BSHR", arity = 2, rlits = gen.SHIFT_COUNTS,
      rlit_kind = K.KINT },
    { name = "BSAR", arity = 2, rlits = gen.SHIFT_COUNTS,
      rlit_kind = K.KINT },
  },
}

-- The leaf operand universe for a type: `ninputs` SLOAD refs
-- (1-based stream indices) followed by the fold-rule constants.
-- The fixed prologue that sources `ninputs` typed input values,
-- plus the stream refs those values live at. num/int read a Lua
-- stack slot directly (SLOAD); i64 has no direct stack form, so
-- it reads an int SLOAD and widens it with CONV int->i64 SEXT --
-- the recorder's own way to get an i64 from a Lua number
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

-- The leaf operand universe for a type: the input value refs
-- (from prologue_for) followed by the fold-rule constants of that
-- type.
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

-- All (op-descriptor, insn-tail) applications at a position,
-- given the value operand(s) available. `val` is the single value
-- operand for a chain step (prev ref at level > 1); at level 1
-- both operands come from the leaf set so `val` is nil and
-- `left`/`right` iterate. Yields a partial insn
-- {op,t,ak,av,bk,bv} (without the stream slot, which the caller
-- assigns) via callback `emit`.
local function each_application(t, leaves, op, level, prev, emit)
  local opnum = gen.op_num(op.name)
  -- ADDOV/SUBOV/MULOV are guards *and* value producers: the
  -- overflow check becomes a trace exit while the wrapped result
  -- stays on the op stack (see ir/ADDOV.lua).
  local ty = op.guard and (t + 0x80) or t
  local function ins(ak, av, bk, bv)
    -- Ops whose recorder guards the divisor non-zero take only a
    -- non-zero constant on the right: a ref can still fold to
    -- zero further down, and kfold divides on the hardware.
    if op.no_zero_right and (bk == K.REF or bv == 0) then return end
    emit({ op = opnum, t = ty, ak = ak, av = av, bk = bk, bv = bv })
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

  -- Fixed prologue (SLOADs, plus CONVs for i64); body refs
  -- follow.
  local prologue = prologue_for(t, ninputs)
  local nprologue = #prologue

  local body = {}   -- current chain being built (partial insns)

  -- Recursively fill body[level]; at level > depth, yield the
  -- trace.
  local function rec(level, prev)
    if level > depth then
      local insns = {}
      for _, x in ipairs(prologue) do insns[#insns + 1] = x end
      for _, x in ipairs(body) do insns[#insns + 1] = x end
      -- Strict linear chain: the sole observable value is the
      -- last op (level `depth`). Using it directly rather than
      -- roots() keeps a dead input source (e.g. an unused i64
      -- CONV) from being compared as a spurious extra output.
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
-- Cheap closed form per level, so a driver can print the total
-- and decide a limit before committing to a run.
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
-- sign-extended as the recorder does it, num->int uses
-- IRCONV_ANY, etc.). Types are limited to the ones ljopt fully
-- models (int/i64/num); u32/u64/narrow/flt are added once ljopt
-- learns them.

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

-- CONV transitions: from-type -> list of {to = type, mode = op2}.
-- Mode = (dst<<IRCONV_DSH)|src [|IRCONV_SEXT for signed widen]
-- [|IRCONV_ANY for num->int]. IRCONV_DSH=5, SEXT=0x800,
-- ANY=0x1000.
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
    -- bit.tobit: num -> int by the "add 2^52+2^51" trick. op2 is
    -- the bias KNUM (lj_ir_knum_tobit = 0x4338000000000000),
    -- which ljopt ignores -- it models the op directly as RNE
    -- fp->int. Reaches LJFOLD(TOBIT KNUM KNUM) and the TOBIT
    -- ADD/SUB/CONV simplifications.
    { to = IRT_INT, op = "TOBIT", bk = K.KNUM,
      mode = 6755399441055744 },
  },
  [IRT_FLT] = {
    { to = IRT_NUM, mode = cmode(IRT_NUM, IRT_FLT) },  -- widen to double
  },
}

-- Enumerate every mixed-type chain of `depth` steps starting from
-- a single int SLOAD. opts: { depth = 3 }. Yields { insns,
-- outputs } like iter().
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
        -- Same non-zero divisor rule as each_application: a
        -- zero constant, or a ref that folds to one, reaches
        -- the hardware divide in kfold.
        if not (op.no_zero_right and c == 0) then
          body[level] = { op = opnum, t = cur_type,
            ak = K.REF, av = prev_ref, bk = cinfo.kind, bv = c }
          rec(level + 1, cur_type, this_ref)
        end
        if not op.commut and not op.no_zero_right then
          body[level] = { op = opnum, t = cur_type,
            ak = cinfo.kind, av = c, bk = K.REF, bv = prev_ref }
          rec(level + 1, cur_type, this_ref)
        end
      end
    end
    -- (b) CONV to another modeled type.
    for _, tr in ipairs(MIXED_CONV[cur_type]) do
      body[level] = { op = gen.op_num(tr.op or "CONV"), t = tr.to,
        ak = K.REF, av = prev_ref,
        bk = tr.bk or K.LIT, bv = tr.mode }
      rec(level + 1, tr.to, this_ref)
      -- Also convert a constant, not just the chain value: the
      -- kfold_conv_k* rules and TOBIT KNUM KNUM match on a
      -- constant source, which a ref chain never presents.
      for _, c in ipairs(cinfo.consts) do
        body[level] = { op = gen.op_num(tr.op or "CONV"), t = tr.to,
          ak = cinfo.kind, av = c,
          bk = tr.bk or K.LIT, bv = tr.mode }
        rec(level + 1, tr.to, this_ref)
      end
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

-- -- Guard (comparison) enumeration ---------------------------
--
-- Comparisons are the only *guard* instructions in the arithmetic
-- subset: they produce no value, they produce a trace exit. A
-- fold that removes one (e.g. LJFOLD(UGE any KINT) drops
-- `x >=u 0`) is only observable through the snapshot trace-exit
-- bitvector, which is why check.lua has to hand the guards to a
-- snapshot -- see the two-snapshot construction in
-- attach_snapshot.
--
-- Recorder reachability (all confirmed against emit sites):
--   int  -- IRTGI(IR_*), lj_ffrecord.c / lj_record.c
--   num  -- IRTG(irop, IRT_NUM), lj_record.c rec_comp; the
--           `irop ^= 4` path is what makes the *unordered* U*
--           forms reachable
--   i64  -- IRTG(op, dt), lj_crecord.c cdata compare;
--           LJ_POST_FIXGUARD supplies the negated
--           (NE/GE/GT/UGE/UGT) forms
local CMP_OPS = {
  "LT", "GE", "LE", "GT", "ULT", "UGE", "ULE", "UGT", "EQ", "NE",
}

local GUARD_TYPES = { IRT_INT, IRT_NUM, IRT_I64 }
local IRT_GUARD = 0x80

-- Enumerate guarded comparisons of every op over every modeled
-- type. `depth` arithmetic steps are prepended so the compare
-- sees a computed (not just loaded) operand, which is what
-- reaches the reassociating compare folds.
-- opts: { depth = 0, types = {...} }.
--
-- Operand shapes, all linear-chain legal:
--   (ref, const)  (const, ref)  (const, const)  (ref, ref)
-- The (const, const) shape is what triggers the kfold compare
-- rules (LT KINT KINT and friends); (ref, ref) is the reflexive
-- `x < x` form.
local function iter_guard(opts)
  opts = opts or {}
  local depth = opts.depth or 0
  local types = opts.types or GUARD_TYPES

  return coroutine.wrap(function()
    for _, t in ipairs(types) do
      local prologue = prologue_for(t, 1)
      local cinfo = MIXED_CONST[t]
      local base = #prologue
      -- Value ref after the prologue.
      local vref = (t == IRT_I64) and 2 or 1

      -- Arithmetic prefixes of exactly `depth` steps, reusing the
      -- mixed-mode same-type op menu.
      local prefixes = {}
      local body = {}
      local function build_prefix(level, prev)
        if level > depth then
          local copy = {}
          for i, x in ipairs(body) do copy[i] = x end
          prefixes[#prefixes + 1] = { insns = copy, ref = prev }
          return
        end
        local this_ref = base + level
        for _, op in ipairs(MIXED_ARITH[t]) do
          for _, c in ipairs(cinfo.consts) do
            body[level] = { op = gen.op_num(op.name), t = t,
              ak = K.REF, av = prev, bk = cinfo.kind, bv = c }
            build_prefix(level + 1, this_ref)
          end
        end
        body[level] = nil
      end
      build_prefix(1, vref)

      for _, pre in ipairs(prefixes) do
        local vr = pre.ref
        local cmp_ref = base + depth + 1
        for _, opname in ipairs(CMP_OPS) do
          local opnum = gen.op_num(opname)
          local shapes = {}
          for _, c in ipairs(cinfo.consts) do
            shapes[#shapes + 1] = { K.REF, vr, cinfo.kind, c }
            shapes[#shapes + 1] = { cinfo.kind, c, K.REF, vr }
            for _, c2 in ipairs(cinfo.consts) do
              shapes[#shapes + 1] = { cinfo.kind, c, cinfo.kind, c2 }
            end
          end
          shapes[#shapes + 1] = { K.REF, vr, K.REF, vr }
          for _, s in ipairs(shapes) do
            local insns = {}
            for _, x in ipairs(prologue) do insns[#insns + 1] = x end
            for _, x in ipairs(pre.insns) do insns[#insns + 1] = x end
            insns[#insns + 1] = { op = opnum, t = t + IRT_GUARD,
              ak = s[1], av = s[2], bk = s[3], bv = s[4] }
            -- The compared value is the output; the guard itself
            -- carries no value and is checked via the trace exit.
            coroutine.yield({ insns = insns, outputs = { vr },
              guard_ref = cmp_ref })
          end
        end
      end
    end
  end)
end

local function count_guard(opts)
  opts = opts or {}
  local depth = opts.depth or 0
  local types = opts.types or GUARD_TYPES
  local n = 0
  for _, t in ipairs(types) do
    local nconst = #MIXED_CONST[t].consts
    local nprefix = (#MIXED_ARITH[t] * nconst) ^ depth
    local nshape = nconst * 2 + nconst * nconst + 1
    n = n + nprefix * #CMP_OPS * nshape
  end
  return n
end

-- -- Aliasing enumeration ---------------------------------------
--
-- Targets LuaJIT's load-forwarding and dead-store elimination,
-- which run *as fold rules* and so are reachable from this
-- harness:
--   LJFOLD(ALOAD any)  -> lj_opt_fwd_aload
--   LJFOLD(HLOAD any)  -> lj_opt_fwd_hload
--   LJFOLD(ASTORE ...) -> lj_opt_dse_ahstore
-- Unlike constant folding, these depend on alias analysis
-- (aa_ahref in lj_opt_mem.c) deciding whether a load may see
-- past a store. Getting that wrong is a miscompile, and random
-- generation almost never produces the store/load pairs that
-- exercise it -- hence an explicit enumeration.
--
-- Shapes emitted, per (access kind, table pair, key pair):
--   store;load          -- may the load forward the stored value?
--   store;store;load    -- is the first store dead?
--   load;store;load     -- may the second load reuse the first?
--
-- The table pair matters most. Two *distinct* SLOAD tab slots may
-- still hold the same table at run time, so AA must stay
-- conservative; a wrong "definitely disjoint" is exactly the bug
-- class worth hunting.
local function iter_alias(opts)
  opts = opts or {}
  local ntab = 2
  local IRT_TAB, IRT_P32 = gen.IRT_TAB, gen.IRT_P32
  local SL = gen.op_num("SLOAD")

  -- Key sets per access kind. Array indices go through
  -- FLOAD tab.array + AREF; hash keys through HREF.
  local KINDS = {
    { name = "array", keys = gen.ARR_IDXS,
      load = "ALOAD", store = "ASTORE" },
    { name = "hash", keys = gen.HASH_KEYS,
      load = "HLOAD", store = "HSTORE" },
  }
  local SHAPES = { "store_load", "store_store_load", "load_store_load" }

  return coroutine.wrap(function()
    for _, kind in ipairs(KINDS) do
      for ta = 1, ntab do
        for tb = 1, ntab do
          for _, ka in ipairs(kind.keys) do
            for _, kb in ipairs(kind.keys) do
              for _, shape in ipairs(SHAPES) do
                local insns = {}
                local function add(x)
                  insns[#insns + 1] = x
                  return #insns
                end
                -- Prologue: two DISTINCT num values + two table
                -- SLOADs. The second value matters for DSE: a
                -- dead-store shape that writes the same value
                -- twice is vacuous, because dse_ahstore's
                -- ALIAS_MAY case only conflicts when the stored
                -- value differs (`store->op2 != val`), so eliding
                -- a same-value store is always correct regardless
                -- of aliasing. Distinct values make "the wrong
                -- store survived" observable in the load.
                local vref = add({ op = SL, t = IRT_NUM, ak = K.LIT,
                  av = 1, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
                local vref2 = add({ op = SL, t = IRT_NUM, ak = K.LIT,
                  av = 2, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
                local tref = {}
                for i = 1, ntab do
                  tref[i] = add({ op = SL, t = IRT_TAB, ak = K.LIT,
                    av = 2 + i, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
                end
                -- Element ref for table `t` at key `k`.
                local abase = {}
                local function eref(t, k)
                  if kind.name == "array" then
                    if not abase[t] then
                      abase[t] = add({ op = gen.op_num("FLOAD"),
                        t = IRT_P32, ak = K.REF, av = tref[t],
                        bk = K.LIT, bv = gen.FIELD_TAB_ARRAY })
                    end
                    return add({ op = gen.op_num("AREF"), t = IRT_P32,
                      ak = K.REF, av = abase[t], bk = K.KINT, bv = k })
                  end
                  return add({ op = gen.op_num("HREF"), t = IRT_P32,
                    ak = K.REF, av = tref[t], bk = K.KINT, bv = k })
                end
                -- store_at/load_at take a *precomputed* element
                -- ref so a shape can control instruction ordering
                -- (DSE needs the two stores adjacent -- see
                -- below).
                local function store_at(ref, val)
                  add({ op = gen.op_num(kind.store), t = IRT_NUM,
                    ak = K.REF, av = ref, bk = K.REF, bv = val })
                end
                local function load_at(ref)
                  return add({ op = gen.op_num(kind.load), t = IRT_NUM,
                    ak = K.REF, av = ref, bk = K.NONE, bv = 0 })
                end
                local function store(t, k, val)
                  store_at(eref(t, k), val)
                end
                local function load(t, k)
                  return load_at(eref(t, k))
                end

                local outputs
                if shape == "store_load" then
                  store(ta, ka, vref)
                  outputs = { load(tb, kb) }
                elseif shape == "store_store_load" then
                  -- DSE. Two requirements make this non-vacuous,
                  -- both found by fault-injecting dse_ahstore
                  -- (MAY-alias treated as MUST):
                  --   * DISTINCT values -- dse_ahstore's MAY case
                  --     only conflicts when the stored value
                  --     differs, so two same-value stores make
                  --     elision always safe regardless of alias.
                  --   * ADJACENT stores -- the elimination bails on
                  --     any intervening guard, and an eref (HREF/
                  --     AREF) between the stores blocks it, so both
                  --     element refs are computed first and the two
                  --     stores emitted back-to-back. The load
                  --     reuses the first ref (as HREF CSE would).
                  -- Verified: clean -> unsat, injected -> SAT.
                  local ea = eref(ta, ka)
                  local eb = eref(tb, kb)
                  store_at(ea, vref)
                  store_at(eb, vref2)
                  outputs = { load_at(ea) }
                else
                  local first = load(ta, ka)
                  store(tb, kb, vref)
                  outputs = { first, load(ta, ka) }
                end
                coroutine.yield({ insns = insns, outputs = outputs })
              end
            end
          end
        end
      end
    end
  end)
end

local function count_alias()
  local n = 0
  for _ in iter_alias() do n = n + 1 end
  return n
end

-- Raw FFI memory (xmem) enumeration. Targets lj_opt_mem.c's
-- aa_xref plus the store-to-load forwarding conversion: when a
-- forwarded store's type differs from the load's, LuaJIT rewrites
-- the load into a CONV and picks sign- or zero-extension from the
-- *load* type. aa_xref also declares two types that differ only in
-- signedness to be the same location,
--   ((xa->t.irt - IRT_I8) ^ (xb->t.irt - IRT_I8)) == 1
-- so an i8 store feeding a u8 load must forward through that CONV
-- rather than being treated as a distinct address. Every width
-- here carries an int-typed value, which is what the recorder
-- emits -- LuaJIT has no arithmetic narrower than int, so a narrow
-- XSTORE always takes an int and truncates at the store.
local function iter_xmem(opts)
  opts = opts or {}
  local SL = gen.op_num("SLOAD")
  local ADD = gen.op_num("ADD")
  local XSTORE = gen.op_num("XSTORE")
  local XLOAD = gen.op_num("XLOAD")

  local TYPES = {
    { name = "i8", t = gen.IRT_I8 },
    { name = "u8", t = gen.IRT_U8 },
    { name = "i16", t = gen.IRT_I16 },
    { name = "u16", t = gen.IRT_U16 },
    { name = "int", t = gen.IRT_INT },
  }
  -- Byte offsets from the same base. 0 aliases exactly; 1 and 2
  -- partially overlap a wider access; 4 is disjoint for every
  -- width here.
  local OFFSETS = { 0, 1, 2, 4 }
  local SHAPES = { "store_load", "store_store_load", "load_store_load" }

  return coroutine.wrap(function()
    for _, st in ipairs(TYPES) do
      for _, lt in ipairs(TYPES) do
        for _, off in ipairs(OFFSETS) do
          for _, shape in ipairs(SHAPES) do
            local insns = {}
            local function add(x)
              insns[#insns + 1] = x
              return #insns
            end
            -- Prologue: the int value to store, and a cdata box
            -- whose payload is the base address. `ADD p64 cdt, k`
            -- is exactly how the recorder forms an FFI element
            -- address (see any `arr[i] = v` trace).
            local vref = add({ op = SL, t = gen.IRT_INT, ak = K.LIT,
              av = 1, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            local cref = add({ op = SL, t = gen.IRT_CDT, ak = K.LIT,
              av = 2, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            local function addr(o)
              return add({ op = ADD, t = gen.IRT_P64, ak = K.REF,
                av = cref, bk = K.KINT, bv = 8 + o })
            end
            local pa = addr(0)
            local pb = addr(off)
            local function store(p, ty)
              add({ op = XSTORE, t = ty, ak = K.REF, av = p,
                bk = K.REF, bv = vref })
            end
            local function load(p, ty)
              return add({ op = XLOAD, t = ty, ak = K.REF, av = p,
                bk = K.LIT, bv = 0 })
            end

            local outputs
            if shape == "store_load" then
              store(pa, st.t)
              outputs = { load(pb, lt.t) }
            elseif shape == "store_store_load" then
              store(pa, st.t)
              store(pb, lt.t)
              outputs = { load(pa, st.t) }
            else
              local first = load(pa, st.t)
              store(pb, lt.t)
              outputs = { first, load(pa, st.t) }
            end
            coroutine.yield({ insns = insns, outputs = outputs })
          end
        end
      end
    end
  end)
end

local function count_xmem()
  local n = 0
  for _ in iter_xmem() do n = n + 1 end
  return n
end

-- String enumeration. LuaJIT's fold-reachable string ops that
-- ljopt models are dominated by the STR_LEN family
-- (fold_str_len_kgc: #<const> -> const length). We exercise it
-- directly (`#s`) and composed with int arithmetic and integer
-- comparisons over pairs of constant strings, so the length fold
-- has to stay consistent through a small dataflow chain. Every
-- result is an int, so z3 only reasons about integers -- full
-- String-theory content reasoning (expensive, often UNKNOWN) is
-- avoided. Validated non-vacuous by injecting `len + 1` into
-- fold_str_len_kgc: clean 0 SAT, injected all SAT.
local function iter_strings()
  local FLOAD = gen.op_num("FLOAD")
  local STRS = gen.STR_CONSTS
  -- Binary int ops (value results) and guard compares.
  local VALOPS = { "ADD", "SUB", "MUL", "BAND", "BOR", "BXOR" }
  local CMPOPS = { "LT", "GE", "LE", "GT", "EQ", "NE" }

  return coroutine.wrap(function()
    for _, s1 in ipairs(STRS) do
      -- Bare length: #s1 (the fold in isolation).
      do
        local insns = { { op = FLOAD, t = IRT_INT, ak = K.KSTR,
          av = s1, bk = K.LIT, bv = gen.IRFL_STR_LEN } }
        coroutine.yield({ insns = insns, outputs = { 1 } })
      end
      for _, s2 in ipairs(STRS) do
        -- Two lengths feeding one int op / one compare.
        local function two_len()
          local insns = {
            { op = FLOAD, t = IRT_INT, ak = K.KSTR, av = s1,
              bk = K.LIT, bv = gen.IRFL_STR_LEN },
            { op = FLOAD, t = IRT_INT, ak = K.KSTR, av = s2,
              bk = K.LIT, bv = gen.IRFL_STR_LEN },
          }
          return insns
        end
        for _, op in ipairs(VALOPS) do
          local insns = two_len()
          insns[3] = { op = gen.op_num(op), t = IRT_INT,
            ak = K.REF, av = 1, bk = K.REF, bv = 2 }
          coroutine.yield({ insns = insns, outputs = { 3 } })
        end
        for _, op in ipairs(CMPOPS) do
          -- Guard compares: the trace-exit oracle checks them
          -- (no value slot). A number leaf keeps the snapshot
          -- non-empty so the compare is observable.
          local insns = two_len()
          insns[3] = { op = gen.op_num(op), t = IRT_INT + 0x80,
            ak = K.REF, av = 1, bk = K.REF, bv = 2 }
          coroutine.yield({ insns = insns, outputs = { 1 } })
        end
      end
    end
  end)
end

local function count_strings()
  local n = 0
  for _ in iter_strings() do n = n + 1 end
  return n
end

-- -- FP-narrowing enumeration ---------------------------------
--
-- lj_opt_narrow.c has exactly one IR-level entry: the
-- narrow_convert fold rule (LJFOLD CONV ADD/SUB IRCONV_INT_NUM,
-- CONV ADD/SUB IRCONV_I64_NUM, TOBIT ADD/SUB KNUM). Every other
-- function in that file is called by the *recorder*
-- (narrow_arith, narrow_index, narrow_forl, ...), which an IR
-- replay never runs, so this shape family is the whole reachable
-- surface.
--
-- When a num ADD/SUB tree is converted back to an integer, LuaJIT
-- back-propagates the conversion into the tree and re-emits the
-- arithmetic at integer width. The enumeration is built around
-- the branches of narrow_conv_backprop, one leaf kind per branch:
--
--   CONV num<-int  -- narrowable: the conversion is undone
--   the same over an ADDOV/SUBOV/MULOV
--                  -- narrow_stripov_backprop, which also
--                     drops the overflow check
--   KNUM           -- narrowed only if it survives the range
--                     test: checki16 for CONV, the wider
--                     int64 range for TOBIT
--   num SLOAD      -- NOT narrowable: costs one conversion,
--                     so one is accepted (count <= 1), and two
--                     make backprop bail and leave the tree
--
-- and around the sink's mode, which decides how much is provable:
-- IRCONV_ANY is a plain C truncation, INDEX/CHECK make the CONV a
-- guard and so make narrow_conv_emit emit overflow-checked ADDOV
-- instead of ADD.
local ANY_, CHECK_ = 0x1000, 0x3000
local TOBIT_BIAS = 6755399441055744  -- 2^52 + 2^51

-- Sinks: the conversion applied to the tree root. `guard` marks
-- the modes LuaJIT emits as a trace exit (INDEX/CHECK), which is
-- what makes narrow_conv_emit attach the ADDOV overflow check.
local NARROW_SINKS = {
  { name = "int_any", op = "CONV", t = IRT_INT,
    bv = IRT_INT * 32 + IRT_NUM + ANY_ },
  -- No IRCONV_INDEX sink. The mode itself is recorder-reachable
  -- (lj_opt_narrow_index, lj_record.c:1882), but only ever
  -- feeding an ABC bounds check, and narrow_conv_emit leans on
  -- that: with a small constant last operand it sets guardot = 0
  -- and drops the overflow check entirely, leaving the narrowed
  -- trace with no exit where the original CONV had one. That is
  -- sound only because the ABC re-checks the range. In an
  -- isolated trace -- ljopt models no ABC node, so one cannot be
  -- added -- the two exit bitvectors just differ, which reads as
  -- a miscompile on every out-of-range input.
  { name = "int_check", op = "CONV", t = IRT_INT + 0x80,
    bv = IRT_INT * 32 + IRT_NUM + CHECK_ },
  { name = "i64_any", op = "CONV", t = IRT_I64,
    bv = IRT_I64 * 32 + IRT_NUM + ANY_ },
  -- No guarded i64 sink: RECORDER_IMPOSSIBLE. Every CHECK/INDEX
  -- num->integer CONV LuaJIT emits is IRCONV_INT_NUM through
  -- IRTGI (lj_record.c:522/1882, lj_ffrecord.c:546,
  -- lj_opt_loop.c:350, lj_opt_narrow.c:458), i.e. int32; the
  -- i64/intp conversions in lj_crecord.c and narrow_cindex are
  -- all IRCONV_ANY, which is not a guard. Generating `CONV i64
  -- num check` narrows to an i64 ADDOV -- an instruction no emit
  -- site produces, since narrow_conv_emit only attaches guardot
  -- when the sink is a guard and every guarded sink is int32. It
  -- also reports false divergences: the narrowing moves the
  -- integrality check from `x + k` onto `x`, which for |x| > 2^53
  -- is a real precision difference, harmless only because the
  -- shape cannot occur. bit.tobit: op2 is the bias KNUM, and
  -- nc.mode is IRCONV_TOBIT.
  { name = "tobit", op = "TOBIT", t = IRT_INT, bk = K.KNUM,
    bv = TOBIT_BIAS },
}

-- KNUM leaves, chosen for the range tests in the KNUM branch:
-- 0/1/-1/100 narrow either way; 32767 is the last checki16 value
-- and 32768 the first one rejected; 1e10 is out of int16 range
-- but inside int64, so only TOBIT narrows it; 3.14 is non-
-- integral and narrows under neither.
local NARROW_KNUMS = {
  0.0, 1.0, -1.0, 100.0, 32767.0, 32768.0, 1e10, 3.14,
}

local function iter_narrow(opts)
  opts = opts or {}
  local SL, CONV = gen.op_num("SLOAD"), gen.op_num("CONV")
  local NUM_INT = IRT_NUM * 32 + IRT_INT
  local OVOPS = { "ADDOV", "SUBOV", "MULOV" }

  -- Prologue, shared by every shape. Refs are fixed so the tree
  -- builders can name them directly.
  local function prologue()
    local p = {
      { op = SL, t = IRT_INT, ak = K.LIT, av = 1,
        bk = K.LIT, bv = gen.SLOAD_TYPECHECK },       -- 1: i
      { op = SL, t = IRT_INT, ak = K.LIT, av = 2,
        bk = K.LIT, bv = gen.SLOAD_TYPECHECK },       -- 2: j
      { op = SL, t = IRT_NUM, ak = K.LIT, av = 3,
        bk = K.LIT, bv = gen.SLOAD_TYPECHECK },       -- 3: x
      { op = CONV, t = IRT_NUM, ak = K.REF, av = 1,
        bk = K.LIT, bv = NUM_INT },                   -- 4: (num)i
      { op = CONV, t = IRT_NUM, ak = K.REF, av = 2,
        bk = K.LIT, bv = NUM_INT },                   -- 5: (num)j
    }
    return p
  end
  local NPRO = 5
  -- Leaf descriptors over the prologue: a ref or a KNUM.
  local LEAVES = {
    { k = K.REF, v = 4 },   -- narrowable
    { k = K.REF, v = 5 },   -- narrowable, distinct source
    { k = K.REF, v = 3 },   -- num SLOAD: costs a conversion
  }
  for _, c in ipairs(NARROW_KNUMS) do
    LEAVES[#LEAVES + 1] = { k = K.KNUM, v = c }
  end
  -- Depth-2 trees multiply out fast, so they run on a reduced
  -- leaf set that still has one of every branch.
  local LEAVES2 = { LEAVES[1], LEAVES[2], LEAVES[3],
                    { k = K.KNUM, v = 1.0 },
                    { k = K.KNUM, v = 32768.0 } }
  local TREEOPS = { "ADD", "SUB" }

  return coroutine.wrap(function()
    local function yield_shape(insns, root)
      for _, sink in ipairs(NARROW_SINKS) do
        local out = {}
        for _, x in ipairs(insns) do out[#out + 1] = x end
        out[#out + 1] = { op = gen.op_num(sink.op), t = sink.t,
          ak = K.REF, av = root,
          bk = sink.bk or K.LIT, bv = sink.bv }
        coroutine.yield({ insns = out, outputs = { #out } })
      end
    end

    -- (a) depth-1 trees: op(leaf, leaf).
    for _, opn in ipairs(TREEOPS) do
      for _, a in ipairs(LEAVES) do
        for _, b in ipairs(LEAVES) do
          local insns = prologue()
          insns[NPRO + 1] = { op = gen.op_num(opn), t = IRT_NUM,
            ak = a.k, av = a.v, bk = b.k, bv = b.v }
          yield_shape(insns, NPRO + 1)
        end
      end
    end

    -- (b) depth-2 trees: op2(op1(leaf, leaf), leaf). Exercises
    -- the recursion, the per-branch conversion budget (count <=
    -- 1) and the backtracking when it is exceeded.
    for _, op1 in ipairs(TREEOPS) do
      for _, op2 in ipairs(TREEOPS) do
        for _, a in ipairs(LEAVES2) do
          for _, b in ipairs(LEAVES2) do
            for _, c in ipairs(LEAVES2) do
              local insns = prologue()
              insns[NPRO + 1] = { op = gen.op_num(op1),
                t = IRT_NUM,
                ak = a.k, av = a.v, bk = b.k, bv = b.v }
              insns[NPRO + 2] = { op = gen.op_num(op2),
                t = IRT_NUM,
                ak = K.REF, av = NPRO + 1, bk = c.k, bv = c.v }
              yield_shape(insns, NPRO + 2)
            end
          end
        end
      end
    end

    -- (c) overflow-checked source: narrow_stripov_backprop only
    -- runs on an ADDOV/SUBOV/MULOV *under* a CONV num<-int, and
    -- MULOV only under IRCONV_ANY.
    for _, ov in ipairs(OVOPS) do
      for _, opn in ipairs(TREEOPS) do
        for _, b in ipairs(LEAVES) do
          local insns = prologue()
          insns[NPRO + 1] = { op = gen.op_num(ov),
            t = IRT_INT + 0x80,
            ak = K.REF, av = 1, bk = K.REF, bv = 2 }
          insns[NPRO + 2] = { op = CONV, t = IRT_NUM,
            ak = K.REF, av = NPRO + 1, bk = K.LIT, bv = NUM_INT }
          insns[NPRO + 3] = { op = gen.op_num(opn), t = IRT_NUM,
            ak = K.REF, av = NPRO + 2, bk = b.k, bv = b.v }
          yield_shape(insns, NPRO + 3)
        end
      end
    end

    -- (d) two sinks over a shared subtree. The first sink's
    -- backpropagation leaves CONVs and bpc cache entries behind,
    -- so the second one takes the "already there" CSE path and
    -- the narrow_bpc_get hit -- neither of which a single sink
    -- reaches.
    for _, s1 in ipairs(NARROW_SINKS) do
      for _, s2 in ipairs(NARROW_SINKS) do
        for _, a in ipairs(LEAVES2) do
          local insns = prologue()
          insns[NPRO + 1] = { op = gen.op_num("ADD"), t = IRT_NUM,
            ak = K.REF, av = 4, bk = a.k, bv = a.v }
          insns[NPRO + 2] = { op = gen.op_num(s1.op), t = s1.t,
            ak = K.REF, av = NPRO + 1,
            bk = s1.bk or K.LIT, bv = s1.bv }
          -- Second tree extends the first, so its backprop
          -- revisits the already-converted subtree.
          insns[NPRO + 3] = { op = gen.op_num("ADD"), t = IRT_NUM,
            ak = K.REF, av = NPRO + 1, bk = K.REF, bv = 5 }
          insns[NPRO + 4] = { op = gen.op_num(s2.op), t = s2.t,
            ak = K.REF, av = NPRO + 3,
            bk = s2.bk or K.LIT, bv = s2.bv }
          coroutine.yield({ insns = insns,
            outputs = { NPRO + 2, NPRO + 4 } })
        end
      end
    end

    -- (e) deep linear chains. Both backpropagators bound
    -- themselves twice over -- by recursion depth
    -- (NARROW_MAX_BACKPROP = 100) and by stack-machine space
    -- (NARROW_MAX_STACK = 256, ~2 entries per level) -- and on
    -- hitting either they rewind `nc->sp` and give up, which is
    -- also the only way narrow_convert ever returns NEXTFOLD. A
    -- short chain never reaches those; these lengths straddle
    -- both limits.
    for _, len in ipairs({ 8, 90, 130, 200 }) do
      local DEEP = { LEAVES[1], LEAVES[3],
                     { k = K.KNUM, v = 1.0 } }
      for _, a in ipairs(DEEP) do
        local insns = prologue()
        local prev = 4  -- (num)i
        for _ = 1, len do
          insns[#insns + 1] = { op = gen.op_num("ADD"),
            t = IRT_NUM,
            ak = K.REF, av = prev, bk = a.k, bv = a.v }
          prev = #insns
        end
        yield_shape(insns, prev)
      end
    end

    -- (f) deep and repeated overflow-checked chains.
    -- narrow_stripov_ backprop keeps its own bpc cache keyed on
    -- IRCONV_TOBIT, so the cache hit needs the SAME ADDOV subtree
    -- stripped twice -- one sink can never do it -- and its depth
    -- backtrack needs a chain long enough to exhaust the shared
    -- stack.
    for _, ov in ipairs(OVOPS) do
      for _, len in ipairs({ 1, 4, 300 }) do
        local insns = prologue()
        local prev = 1  -- int i
        for _ = 1, len do
          insns[#insns + 1] = { op = gen.op_num(ov),
            t = IRT_INT + 0x80,
            ak = K.REF, av = prev, bk = K.REF, bv = 2 }
          prev = #insns
        end
        local dov = #insns + 1
        insns[dov] = { op = CONV, t = IRT_NUM,
          ak = K.REF, av = prev, bk = K.LIT, bv = NUM_INT }
        -- Two ADD trees over the same converted chain, each with
        -- its own sink, so the second strip finds the first in
        -- the cache.
        insns[dov + 1] = { op = gen.op_num("ADD"), t = IRT_NUM,
          ak = K.REF, av = dov, bk = K.KNUM, bv = 1.0 }
        insns[dov + 2] = { op = gen.op_num("ADD"), t = IRT_NUM,
          ak = K.REF, av = dov, bk = K.KNUM, bv = 2.0 }
        for _, s1 in ipairs(NARROW_SINKS) do
          for _, s2 in ipairs(NARROW_SINKS) do
            local out = {}
            for _, x in ipairs(insns) do out[#out + 1] = x end
            out[dov + 3] = { op = gen.op_num(s1.op), t = s1.t,
              ak = K.REF, av = dov + 1,
              bk = s1.bk or K.LIT, bv = s1.bv }
            out[dov + 4] = { op = gen.op_num(s2.op), t = s2.t,
              ak = K.REF, av = dov + 2,
              bk = s2.bk or K.LIT, bv = s2.bv }
            coroutine.yield({ insns = out,
              outputs = { dov + 3, dov + 4 } })
          end
        end
      end
    end
  end)
end

local function count_narrow()
  local n = 0
  for _ in iter_narrow() do n = n + 1 end
  return n
end

-- -- Allocation-sinking enumeration ---------------------------
--
-- lj_opt_sink.c runs after FOLD/DCE and does nothing at all
-- unless the trace still holds a TNEW/TDUP/CNEW/CNEWI, so none
-- of it is
-- reachable from the arithmetic and SLOAD-table shapes above: an
-- allocation has to be created *inside* the trace. What sinking
-- then decides is whether that allocation ever has to exist in
-- memory. It may be elided when nothing outside the trace can
-- observe it; the stores into it are elided with it and replayed
-- from the snapshot on a trace exit.
--
-- WHAT THIS DOES AND DOES NOT CHECK. Sinking is not observable
-- in an IR-only replay: sink_sweep_ins() records its decision in
-- `ir->prev` (a register hint the assembler reads) and clears
-- IRT_GUARD on the allocation, and neither reaches the decoded
-- IR. Fault injection confirms it -- with sink_mark_ins() stubbed
-- out, so that every allocation is sunk however it is used, all
-- 120 traces still come back unsat. What the sweep does check is
-- everything FOLD and lj_opt_mem.c do to a table the trace
-- allocated itself, which the SLOAD-table shapes never reach:
-- forcing aa_ahref() to ALIAS_MUST turns 18 of the 120 SAT.
-- Sinking itself is covered here, not verified.
--
-- sink_mark_ins() decides which allocations are eligible, so the
-- enumeration walks the reasons it has to mark one non-sinkable:
--
--   * the allocation is live in a snapshot (`escape`),
--   * a load still reads it (ALOAD/HLOAD/FLOAD tab.meta, TBAR),
--   * a store addresses it through a reference sink_checkalloc()
--     does not recognize -- a non-constant key, or a table that
--     is not an allocation at all (SLOAD),
--   * the allocation is itself a stored value (`nested`).
--
-- Not emitted: TDUP needs a template-table constant and CNEW a
-- live ctype, neither of which the harness can intern (there is
-- no KGC operand kind); HREFK needs a KSLOT operand, which only
-- the recorder's constant-key lookup builds. All four take the
-- same sink_checkalloc()/sink_sweep_ins() paths as TNEW.
--
-- Also not emitted: a metatable store (FREF tab.meta + FSTORE).
-- ljopt has no FREF node, and the one FSTORE impl copies a whole
-- table rather than writing a field, so such a shape translates
-- to something that is not the store it stands for -- it would
-- read unsat without proving anything.
local FIELD_TAB_META = 5  -- jit.vmdef.irfield, next to tab.array
local IRT_NIL = 0         -- TBAR carries no value

local SINK_ALLOCS = {
  { name = "arr", asize = 4, hbits = 0 },
  { name = "hash", asize = 0, hbits = 2 },
  { name = "both", asize = 2, hbits = 1 },
}

-- How a store addresses the allocation. This is exactly what
-- sink_checkalloc() switches on, and only `aref` / `newref` are
-- eligible; the other two must keep the allocation alive.
local SINK_REFS = {
  "aref",      -- FLOAD tab.array + AREF, constant index
  "aref_var",  -- same, but a loaded index: non-constant key
  "newref",    -- NEWREF, the hash-part store the recorder emits
  "sload",     -- store into an SLOAD table: not an allocation
}

local SINK_SHAPES = {
  "store_load",        -- store, then read it back
  "store_store_load",  -- second store to another key must not
                       -- clobber the first
  "nested",            -- store the allocation into another one
  "tbar",              -- TBAR keeps the table observable
  "meta",              -- FLOAD tab.meta keeps it observable
}

local function iter_sink(opts)
  opts = opts or {}
  local IRT_TAB, IRT_P32 = gen.IRT_TAB, gen.IRT_P32
  local SL = gen.op_num("SLOAD")
  -- Guarded: a TNEW can fail and exit, which is what makes the
  -- allocation a snapshot root before sinking clears the flag.
  local TNEW_T = IRT_TAB + 0x80

  return coroutine.wrap(function()
    for _, alloc in ipairs(SINK_ALLOCS) do
      for _, refkind in ipairs(SINK_REFS) do
        for _, shape in ipairs(SINK_SHAPES) do
          for _, escape in ipairs({ false, true }) do
            local insns = {}
            local function add(x)
              insns[#insns + 1] = x
              return #insns
            end
            -- Two distinct values, so a store the optimizer
            -- wrongly dropped is visible in the load (a shape
            -- storing the same value twice is vacuous).
            local v1 = add({ op = SL, t = IRT_NUM, ak = K.LIT,
              av = 1, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            local v2 = add({ op = SL, t = IRT_NUM, ak = K.LIT,
              av = 2, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            local idx = add({ op = SL, t = IRT_INT, ak = K.LIT,
              av = 3, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            local tab = add({ op = SL, t = IRT_TAB, ak = K.LIT,
              av = 4, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            local tn = add({ op = gen.op_num("TNEW"), t = TNEW_T,
              ak = K.LIT, av = alloc.asize,
              bk = K.LIT, bv = alloc.hbits })
            -- The `sload` kind still allocates: without a TNEW in
            -- the trace lj_opt_sink() returns immediately, so the
            -- "store to a non-allocation" path is never reached.
            local base = refkind == "sload" and tab or tn

            local abase
            local function eref(key, want_var)
              if refkind == "newref" then
                return add({ op = gen.op_num("NEWREF"), t = IRT_P32,
                  ak = K.REF, av = base, bk = K.KINT, bv = -key })
              end
              if not abase then
                abase = add({ op = gen.op_num("FLOAD"), t = IRT_P32,
                  ak = K.REF, av = base,
                  bk = K.LIT, bv = gen.FIELD_TAB_ARRAY })
              end
              if want_var then
                return add({ op = gen.op_num("AREF"), t = IRT_P32,
                  ak = K.REF, av = abase, bk = K.REF, bv = idx })
              end
              return add({ op = gen.op_num("AREF"), t = IRT_P32,
                ak = K.REF, av = abase, bk = K.KINT, bv = key })
            end
            local sop = refkind == "newref" and "HSTORE" or "ASTORE"
            local lop = refkind == "newref" and "HLOAD" or "ALOAD"
            local function store_at(ref, val, t)
              add({ op = gen.op_num(sop), t = t or IRT_NUM,
                ak = K.REF, av = ref, bk = K.REF, bv = val })
            end
            local function load_at(ref, t)
              return add({ op = gen.op_num(lop), t = t or IRT_NUM,
                ak = K.REF, av = ref, bk = K.NONE, bv = 0 })
            end
            local var = refkind == "aref_var"
            local outputs = {}
            if shape == "store_store_load" then
              local e1 = eref(1, var)
              local e2 = eref(2, var)
              store_at(e1, v1)
              store_at(e2, v2)
              outputs[#outputs + 1] = load_at(e1)
            elseif shape == "nested" then
              -- Storing the allocation into another table makes
              -- it a stored value, which sink_mark_ins() marks.
              -- The store target is always the SLOAD table, so
              -- the allocation's eligibility is the only knob.
              local ab = add({ op = gen.op_num("FLOAD"), t = IRT_P32,
                ak = K.REF, av = tab,
                bk = K.LIT, bv = gen.FIELD_TAB_ARRAY })
              local e = add({ op = gen.op_num("AREF"), t = IRT_P32,
                ak = K.REF, av = ab, bk = K.KINT, bv = 3 })
              add({ op = gen.op_num("ASTORE"), t = IRT_TAB,
                ak = K.REF, av = e, bk = K.REF, bv = tn })
              local e1 = eref(1, var)
              store_at(e1, v1)
              outputs[#outputs + 1] = load_at(e1)
            elseif shape == "tbar" then
              local e1 = eref(1, var)
              store_at(e1, v1)
              add({ op = gen.op_num("TBAR"), t = IRT_NIL,
                ak = K.REF, av = base, bk = K.NONE, bv = 0 })
              outputs[#outputs + 1] = load_at(e1)
            elseif shape == "meta" then
              local e1 = eref(1, var)
              store_at(e1, v1)
              -- Emitted but NOT compared. A table pointer read
              -- out of memory is an unconstrained id in ljopt's
              -- model, so the solver may equate it with the fresh
              -- allocation's id; comparing it then reports the
              -- alias as a divergence. The array load below is
              -- what this shape actually checks.
              add({ op = gen.op_num("FLOAD"), t = IRT_TAB,
                ak = K.REF, av = base, bk = K.LIT, bv = FIELD_TAB_META })
              outputs[#outputs + 1] = load_at(e1)
            else
              local e1 = eref(1, var)
              store_at(e1, v1)
              outputs[#outputs + 1] = load_at(e1)
            end
            if escape then
              outputs[#outputs + 1] = tn
            end
            coroutine.yield({ insns = insns, outputs = outputs })
          end
        end
      end
    end
  end)
end

local function count_sink()
  local n = 0
  for _ in iter_sink() do n = n + 1 end
  return n
end

-- -- String-buffer enumeration ---------------------------------
--
-- Lua's `..` does not compile to a concat instruction: the
-- recorder builds a string buffer (BUFHDR) and appends to it
-- (BUFPUT / CALLL lj_buf_*), then materializes the result
-- (BUFSTR). FOLD treats that chain specially -- the rules under
-- "Buffer operations" in lj_opt_fold.c join adjacent constant
-- puts, drop empty ones, short-circuit a one-put buffer, splice a
-- BUFSTR back into a following BUFHDR, and CSE whole chains --
-- and none of it is reachable without emitting the chain itself.
--
-- ljopt models a buffer as a string cell in memory and a BUFPUT
-- as `str.++`, so the sweep is a real oracle here and not just
-- coverage: the folded constant and the symbolic concatenation
-- have to agree.
--
-- Only lj_buf_putstr_reverse is emitted of the CALLL puts. The
-- upper/lower/rep/strfmt calls take the same fold path but ljopt
-- has no model for them, so they would translate to nothing and
-- read unsat vacuously.
local BUF_VALS = { "sym", "", "a", "hi", "abc" }

local BUF_SHAPES = {
  "empty",     -- no put at all: BUFSTR folds to ""
  "put1",      -- one put: BUFSTR is that put's value
  "put2",      -- two puts: adjacent constants join
  "put3",      -- three puts, with the first value repeated
  "cse",       -- two identical chains, both materialized
  "append",    -- BUFSTR fed straight back into a new BUFHDR
  "rev",       -- CALLL lj_buf_putstr_reverse as the only put
  "rev_put",   -- a reverse call followed by an ordinary put
}

local function iter_buffers(opts)
  opts = opts or {}
  local P32, STR = gen.IRT_P32, gen.IRT_STR
  local BUFHDR = gen.op_num("BUFHDR")
  local BUFPUT = gen.op_num("BUFPUT")
  local BUFSTR = gen.op_num("BUFSTR")
  local CARG, CALLL = gen.op_num("CARG"), gen.op_num("CALLL")
  local REVERSE = gen.ircall_num("lj_buf_putstr_reverse")
  local BUFHDR_RESET = 0

  return coroutine.wrap(function()
    for _, va in ipairs(BUF_VALS) do
      for _, vb in ipairs(BUF_VALS) do
        for _, shape in ipairs(BUF_SHAPES) do
          local insns = {}
          local function add(x)
            insns[#insns + 1] = x
            return #insns
          end
          -- One symbolic string, so a shape can mix a constant
          -- put with an unknown one; "sym" selects it.
          local sym = add({ op = gen.op_num("SLOAD"), t = STR,
            ak = K.LIT, av = 1,
            bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
          local function hdr()
            return add({ op = BUFHDR, t = P32, ak = K.KINT, av = 0,
              bk = K.LIT, bv = BUFHDR_RESET })
          end
          -- A put's value is either the symbolic SLOAD (a REF) or
          -- an interned constant (a KSTR).
          local function put(buf, v)
            if v == "sym" then
              return add({ op = BUFPUT, t = P32, ak = K.REF,
                av = buf, bk = K.REF, bv = sym })
            end
            return add({ op = BUFPUT, t = P32, ak = K.REF,
              av = buf, bk = K.KSTR, bv = v })
          end
          local function put_ref(buf, ref)
            return add({ op = BUFPUT, t = P32, ak = K.REF,
              av = buf, bk = K.REF, bv = ref })
          end
          local function reverse(buf, v)
            local arg = sym
            if v ~= "sym" then
              -- A KSTR cannot be a CARG operand directly: the
              -- argument list is built from refs, so intern it
              -- through a put-free BUFPUT-shaped constant is not
              -- possible either. Feed the constant as the CARG's
              -- own operand, which the harness interns.
              arg = nil
            end
            local carg
            if arg then
              carg = add({ op = CARG, t = gen.IRT_NIL, ak = K.REF,
                av = buf, bk = K.REF, bv = arg })
            else
              carg = add({ op = CARG, t = gen.IRT_NIL, ak = K.REF,
                av = buf, bk = K.KSTR, bv = v })
            end
            -- Unguarded, as lj_ir_call() emits it (CCI_OPTYPE for
            -- lj_buf_putstr_reverse carries no IRT_GUARD). It has
            -- to be: ljopt's CALLL node writes no trace-exit
            -- entry, so a guarded one would leave its exit
            -- condition a free boolean and the two sides could
            -- disagree on it for nothing.
            return add({ op = CALLL, t = P32, ak = K.REF,
              av = carg, bk = K.LIT, bv = REVERSE })
          end
          local function bufstr(last, h)
            return add({ op = BUFSTR, t = STR, ak = K.REF,
              av = last, bk = K.REF, bv = h })
          end

          local outputs
          if shape == "empty" then
            local h = hdr()
            outputs = { bufstr(h, h) }
          elseif shape == "put1" then
            local h = hdr()
            outputs = { bufstr(put(h, va), h) }
          elseif shape == "put2" then
            local h = hdr()
            outputs = { bufstr(put(put(h, va), vb), h) }
          elseif shape == "put3" then
            local h = hdr()
            outputs = { bufstr(put(put(put(h, va), vb), va), h) }
          elseif shape == "cse" then
            local h1 = hdr()
            local b1 = bufstr(put(put(h1, va), vb), h1)
            local h2 = hdr()
            local b2 = bufstr(put(put(h2, va), vb), h2)
            outputs = { b1, b2 }
          elseif shape == "append" then
            local h1 = hdr()
            local b1 = bufstr(put(h1, va), h1)
            local h2 = hdr()
            outputs = { bufstr(put(put_ref(h2, b1), vb), h2) }
          elseif shape == "rev" then
            local h = hdr()
            outputs = { bufstr(reverse(h, va), h) }
          else
            local h = hdr()
            outputs = { bufstr(put(reverse(h, va), vb), h) }
          end
          coroutine.yield({ insns = insns, outputs = outputs })
        end
      end
    end
  end)
end

local function count_buffers()
  local n = 0
  for _ in iter_buffers() do n = n + 1 end
  return n
end

-- -- Array-bounds-check enumeration -----------------------------
--
-- COVERAGE ONLY, like the sinking sweep and for the same reason:
-- ljopt has no ABC node, so an eliminated bounds check is
-- invisible to the equivalence query (its exit is pinned true on
-- both sides, see the default in ir_smtlib.translate). What this
-- reaches is lj_opt_fold.c's three ABC rules, which are otherwise
-- dead -- an ABC only ever comes from the recorder's index path.
--
--   abc_k     two constant-key checks on one asize: the wider one
--             replaces the narrower, either order
--   abc_fwd   ABC(asize, (i+k)+(-k)) collapses onto an existing
--             ABC(asize, i)
--   abc_invar a P32/U32-typed check (what the recorder emits for a
--             loop-invariant bound) is dropped inside a loop
local ABC_KEYS = { 1, 3, 5, 100 }

local ABC_SHAPES = {
  "k_two",     -- two constant keys, second wider
  "k_two_rev", -- two constant keys, second narrower
  "k_one",     -- a single constant key
  "fwd",       -- (i+k)+(-k) after a plain ABC(asize, i)
  "fwd_bare",  -- the same index arithmetic with no earlier ABC
  "var",       -- a plain loaded index
  "invar",     -- P32-typed: the loop-invariant check
  "invar_u32", -- U32-typed: the constant-asize invariant check
}

local function iter_abc(opts)
  opts = opts or {}
  local IRT_TAB, IRT_P32, IRT_U32 = gen.IRT_TAB, gen.IRT_P32, gen.IRT_U32
  local SL, ABC = gen.op_num("SLOAD"), gen.op_num("ABC")
  local ADD = gen.op_num("ADD")
  local FIELD_TAB_ASIZE = 8

  return coroutine.wrap(function()
    for _, ka in ipairs(ABC_KEYS) do
      for _, kb in ipairs(ABC_KEYS) do
        for _, shape in ipairs(ABC_SHAPES) do
          local insns = {}
          local function add(x)
            insns[#insns + 1] = x
            return #insns
          end
          local v = add({ op = SL, t = IRT_NUM, ak = K.LIT, av = 1,
            bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
          local idx = add({ op = SL, t = IRT_INT, ak = K.LIT, av = 2,
            bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
          local tab = add({ op = SL, t = IRT_TAB, ak = K.LIT, av = 3,
            bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
          local asize = add({ op = gen.op_num("FLOAD"), t = IRT_INT,
            ak = K.REF, av = tab, bk = K.LIT, bv = FIELD_TAB_ASIZE })
          -- Guarded and int-typed, as emitir(IRTGI(IR_ABC)) does
          -- for an ordinary t[i]; the invariant shapes override
          -- it.
          local function abc(key_kind, key, t)
            add({ op = ABC, t = (t or IRT_INT) + 0x80,
              ak = K.REF, av = asize, bk = key_kind, bv = key })
          end
          -- (i + k) + (-k): the shape abc_fwd recognizes.
          local function roundtrip(k)
            local up = add({ op = ADD, t = IRT_INT, ak = K.REF,
              av = idx, bk = K.KINT, bv = k })
            return add({ op = ADD, t = IRT_INT, ak = K.REF,
              av = up, bk = K.KINT, bv = -k })
          end

          if shape == "k_two" then
            abc(K.KINT, math.min(ka, kb))
            abc(K.KINT, math.max(ka, kb))
          elseif shape == "k_two_rev" then
            abc(K.KINT, math.max(ka, kb))
            abc(K.KINT, math.min(ka, kb))
          elseif shape == "k_one" then
            abc(K.KINT, ka)
          elseif shape == "fwd" then
            abc(K.REF, idx)
            abc(K.REF, roundtrip(ka))
          elseif shape == "fwd_bare" then
            abc(K.REF, roundtrip(ka))
          elseif shape == "invar" then
            abc(K.REF, idx, IRT_P32)
          elseif shape == "invar_u32" then
            abc(K.REF, idx, IRT_U32)
          else
            abc(K.REF, idx)
          end

          -- A real array access under the check, so the trace has
          -- something to compare and the ABC is not
          -- free-floating.
          local abase = add({ op = gen.op_num("FLOAD"), t = IRT_P32,
            ak = K.REF, av = tab, bk = K.LIT, bv = gen.FIELD_TAB_ARRAY })
          local aref = add({ op = gen.op_num("AREF"), t = IRT_P32,
            ak = K.REF, av = abase, bk = K.KINT, bv = ka })
          add({ op = gen.op_num("ASTORE"), t = IRT_NUM,
            ak = K.REF, av = aref, bk = K.REF, bv = v })
          local out = add({ op = gen.op_num("ALOAD"), t = IRT_NUM,
            ak = K.REF, av = aref, bk = K.NONE, bv = 0 })
          coroutine.yield({ insns = insns, outputs = { out } })
        end
      end
    end
  end)
end

local function count_abc()
  local n = 0
  for _ in iter_abc() do n = n + 1 end
  return n
end

-- -- Upvalue enumeration ----------------------------------------
--
-- COVERAGE ONLY: ljopt models neither ULOAD nor USTORE, so every
-- output here is a gap and the sweep proves nothing. It exists
-- because lj_opt_mem.c's aa_uref / lj_opt_fwd_uload /
-- lj_opt_dse_ustore (and fold's cse_uref) are otherwise entirely
-- dead -- upvalue refs only come from the recorder's UPVAL path.
--
-- aa_uref's four answers are what the enumeration walks, and its
-- disambiguation is unusual enough to be worth reaching: an
-- upvalue ref carries `(index << 8) | hash`, so two refs on
-- DIFFERENT functions are provably distinct when their low hash
-- bytes differ, and only MAY-alias when the bytes match.
local UREF_KINDS = { "UREFO", "UREFC" }

-- (upvalue index, disambiguation hash) pairs: same index with a
-- different hash, and a different index with the same hash.
local UREF_UVS = { 0x011, 0x111, 0x022 }

local UPVAL_SHAPES = { "store_load", "store_store_load",
                       "load_store_load" }

local function iter_upval(opts)
  opts = opts or {}
  local IRT_P32, IRT_FUNC = gen.IRT_P32, gen.IRT_FUNC
  local SL = gen.op_num("SLOAD")
  local ULOAD, USTORE = gen.op_num("ULOAD"), gen.op_num("USTORE")

  return coroutine.wrap(function()
    for _, kind in ipairs(UREF_KINDS) do
      for fa = 1, 2 do
        for fb = 1, 2 do
          for _, uva in ipairs(UREF_UVS) do
            for _, uvb in ipairs(UREF_UVS) do
              for _, shape in ipairs(UPVAL_SHAPES) do
                local insns = {}
                local function add(x)
                  insns[#insns + 1] = x
                  return #insns
                end
                -- Two distinct values: a dead-store shape that
                -- writes the same value twice is vacuous.
                local v1 = add({ op = SL, t = IRT_NUM, ak = K.LIT,
                  av = 1, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
                local v2 = add({ op = SL, t = IRT_NUM, ak = K.LIT,
                  av = 2, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
                local fn = {}
                for i = 1, 2 do
                  fn[i] = add({ op = SL, t = IRT_FUNC, ak = K.LIT,
                    av = 2 + i, bk = K.LIT,
                    bv = gen.SLOAD_TYPECHECK })
                end
                local function uref(f, uv)
                  return add({ op = gen.op_num(kind),
                    t = IRT_P32 + 0x80, ak = K.REF, av = fn[f],
                    bk = K.LIT, bv = uv })
                end
                local function store_at(ref, val)
                  add({ op = USTORE, t = IRT_NUM, ak = K.REF,
                    av = ref, bk = K.REF, bv = val })
                end
                local function load_at(ref)
                  return add({ op = ULOAD, t = IRT_NUM + 0x80,
                    ak = K.REF, av = ref, bk = K.NONE, bv = 0 })
                end

                local outputs
                if shape == "store_store_load" then
                  local ea = uref(fa, uva)
                  local eb = uref(fb, uvb)
                  store_at(ea, v1)
                  store_at(eb, v2)
                  outputs = { load_at(ea) }
                elseif shape == "load_store_load" then
                  local first = load_at(uref(fa, uva))
                  store_at(uref(fb, uvb), v1)
                  outputs = { first, load_at(uref(fa, uva)) }
                else
                  store_at(uref(fa, uva), v1)
                  outputs = { load_at(uref(fb, uvb)) }
                end
                coroutine.yield({ insns = insns, outputs = outputs })
              end
            end
          end
        end
      end
    end
  end)
end

local function count_upval()
  local n = 0
  for _ in iter_upval() do n = n + 1 end
  return n
end

-- -- Element-reference enumeration
-- -------------------------------
--
-- iter_alias covers store/load pairs on SLOAD'd tables with
-- constant keys, which is the easy half of aa_ahref(). The half
-- it never reaches is the *index arithmetic*: an AREF key may be
-- `i`, `i+k`, or `(i+k)+(-k)`, and aa_ahref disambiguates
-- `t[base]` from `t[base+-ofs]` structurally rather than by
-- value. fwd_aload_reassoc() then forwards a load across exactly
-- the round-trip form. Neither fires on a constant key.
--
-- Also here, because each needs a shape iter_alias cannot make:
--   * a load from a table with no matching store, which is a
--     constant nil when the table is a TNEW,
--   * a NEWREF with a num key, which forces fwd_ahload to give up
--     on the array part (a num key can rehash into it),
--   * an int key against a num key, so aa_ahref's key-type test
--     decides instead of the key values.
local AHREF_TABS = { "sload_a", "sload_b", "tnew" }

local AHREF_KEYS = {
  "k1",       -- constant 1
  "k2",       -- constant 2
  "i",        -- the loaded index
  "i_add",    -- i + 3
  "i_round",  -- (i + 3) + (-3): what fwd_aload_reassoc matches
}

local AHREF_SHAPES = {
  "store_load", "store_store_load", "load_store_load", "load_only",
}

local function iter_ahref(opts)
  opts = opts or {}
  local IRT_TAB, IRT_P32 = gen.IRT_TAB, gen.IRT_P32
  local SL, ADD = gen.op_num("SLOAD"), gen.op_num("ADD")
  local OFS = 3

  return coroutine.wrap(function()
    for _, ta in ipairs(AHREF_TABS) do
      for _, tb in ipairs(AHREF_TABS) do
        for _, ka in ipairs(AHREF_KEYS) do
          for _, kb in ipairs(AHREF_KEYS) do
            for _, shape in ipairs(AHREF_SHAPES) do
              for _, newref_num in ipairs({ false, true }) do
                local insns = {}
                local function add(x)
                  insns[#insns + 1] = x
                  return #insns
                end
                local v1 = add({ op = SL, t = IRT_NUM, ak = K.LIT,
                  av = 1, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
                local v2 = add({ op = SL, t = IRT_NUM, ak = K.LIT,
                  av = 2, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
                local idx = add({ op = SL, t = IRT_INT, ak = K.LIT,
                  av = 3, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
                local tabs = {}
                tabs.sload_a = add({ op = SL, t = IRT_TAB,
                  ak = K.LIT, av = 4, bk = K.LIT,
                  bv = gen.SLOAD_TYPECHECK })
                tabs.sload_b = add({ op = SL, t = IRT_TAB,
                  ak = K.LIT, av = 5, bk = K.LIT,
                  bv = gen.SLOAD_TYPECHECK })
                tabs.tnew = add({ op = gen.op_num("TNEW"),
                  t = IRT_TAB + 0x80, ak = K.LIT, av = 4,
                  bk = K.LIT, bv = 0 })
                -- A NEWREF with a num key may land in the array
                -- part on rehash, so fwd_ahload stops forwarding
                -- array loads once one exists.
                if newref_num then
                  add({ op = gen.op_num("NEWREF"), t = IRT_P32,
                    ak = K.REF, av = tabs.sload_a,
                    bk = K.KNUM, bv = 1.5 })
                end

                local abase = {}
                local function key_ref(k)
                  if k == "k1" then return K.KINT, 1 end
                  if k == "k2" then return K.KINT, 2 end
                  if k == "i" then return K.REF, idx end
                  local up = add({ op = ADD, t = IRT_INT,
                    ak = K.REF, av = idx, bk = K.KINT, bv = OFS })
                  if k == "i_add" then return K.REF, up end
                  return K.REF, add({ op = ADD, t = IRT_INT,
                    ak = K.REF, av = up, bk = K.KINT, bv = -OFS })
                end
                local function eref(t, k)
                  if not abase[t] then
                    abase[t] = add({ op = gen.op_num("FLOAD"),
                      t = IRT_P32, ak = K.REF, av = tabs[t],
                      bk = K.LIT, bv = gen.FIELD_TAB_ARRAY })
                  end
                  local kk, kv = key_ref(k)
                  return add({ op = gen.op_num("AREF"), t = IRT_P32,
                    ak = K.REF, av = abase[t], bk = kk, bv = kv })
                end
                local function store_at(ref, val)
                  add({ op = gen.op_num("ASTORE"), t = IRT_NUM,
                    ak = K.REF, av = ref, bk = K.REF, bv = val })
                end
                local function load_at(ref)
                  return add({ op = gen.op_num("ALOAD"), t = IRT_NUM,
                    ak = K.REF, av = ref, bk = K.NONE, bv = 0 })
                end

                local outputs
                if shape == "store_store_load" then
                  local ea = eref(ta, ka)
                  local eb = eref(tb, kb)
                  store_at(ea, v1)
                  store_at(eb, v2)
                  outputs = { load_at(ea) }
                elseif shape == "load_store_load" then
                  local first = load_at(eref(ta, ka))
                  store_at(eref(tb, kb), v1)
                  outputs = { first, load_at(eref(ta, ka)) }
                elseif shape == "load_only" then
                  -- No store at all. On a TNEW the load is a
                  -- constant nil, which is the one fwd_ahload
                  -- shortcut nothing else here produces.
                  outputs = { load_at(eref(ta, ka)),
                              load_at(eref(tb, kb)) }
                else
                  store_at(eref(ta, ka), v1)
                  outputs = { load_at(eref(tb, kb)) }
                end
                coroutine.yield({ insns = insns, outputs = outputs })
              end
            end
          end
        end
      end
    end
  end)
end

local function count_ahref()
  local n = 0
  for _ in iter_ahref() do n = n + 1 end
  return n
end

-- -- Substring / string-compare enumeration
-- ----------------------
--
-- COVERAGE ONLY: ljopt models neither SNEW nor STRREF, so the
-- results here are gaps. What it reaches is the `string.sub`
-- family of fold rules, which nothing else can produce:
--
--   kfold_strref_snew     strref(snew(ptr, len), 0) -> ptr, and the
--                         reassociation of a strref of a strref
--   merge_eqne_snew_kgc   `s:sub(a,b) == "abc"` rewritten into
--                         length + unaligned XLOAD compares, for
--                         constant strings up to 4 bytes
--   kfold_strcmp          two constant strings compared
--   fload_str_len_snew    #s:sub(a,b) without building the string
local STROP_BASES = { "kabc", "khello", "sym" }
local STROP_OFFS = { 0, 1, "i" }
-- Lengths 0..4 are the ones merge_eqne_snew_kgc expands; 5 is
-- past FOLD_SNEW_MAX_LEN and must fall through, and "n" is
-- unknown.
local STROP_LENS = { 0, 1, 2, 3, 4, 5, "n" }
local STROP_SHAPES = { "strref0", "strref_re", "eq", "ne", "cmp", "len" }
local STROP_CMP = { "", "a", "ab", "abc", "abcd", "abcde" }

local function iter_strops(opts)
  opts = opts or {}
  local IRT_P32, IRT_STR = gen.IRT_P32, gen.IRT_STR
  local SL = gen.op_num("SLOAD")
  local STRREF, SNEW = gen.op_num("STRREF"), gen.op_num("SNEW")
  local CARG, CALLN = gen.op_num("CARG"), gen.op_num("CALLN")
  local STR_CMP = gen.ircall_num("lj_str_cmp")

  return coroutine.wrap(function()
    for _, base in ipairs(STROP_BASES) do
      for _, ofs in ipairs(STROP_OFFS) do
        for _, len in ipairs(STROP_LENS) do
          for _, shape in ipairs(STROP_SHAPES) do
            local insns = {}
            local function add(x)
              insns[#insns + 1] = x
              return #insns
            end
            local sym = add({ op = SL, t = IRT_STR, ak = K.LIT,
              av = 1, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            local i = add({ op = SL, t = IRT_INT, ak = K.LIT,
              av = 2, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            -- The string a substring is taken of: a constant, so
            -- the constant-folding rules can fire, or an SLOAD so
            -- they must not.
            local function str_operand()
              if base == "sym" then return K.REF, sym end
              return K.KSTR, base == "kabc" and "abc" or "hello"
            end
            local function int_operand(v)
              if v == "i" or v == "n" then return K.REF, i end
              return K.KINT, v
            end
            local function strref(sk, sv, o)
              local ok, ov = int_operand(o)
              return add({ op = STRREF, t = IRT_P32, ak = sk,
                av = sv, bk = ok, bv = ov })
            end
            local function snew(ptr)
              local lk, lv = int_operand(len)
              return add({ op = SNEW, t = IRT_STR, ak = K.REF,
                av = ptr, bk = lk, bv = lv })
            end

            local sk, sv = str_operand()
            local outputs
            if shape == "strref0" then
              -- strref(snew(ptr, len), 0) collapses to ptr.
              local s = snew(strref(sk, sv, ofs))
              outputs = { strref(K.REF, s, 0) }
            elseif shape == "strref_re" then
              -- A strref of a snew of a strref reassociates the
              -- two offsets into one.
              local s = snew(strref(sk, sv, ofs))
              outputs = { strref(K.REF, s, 1) }
            elseif shape == "cmp" then
              local ka, kb = str_operand()
              local c = add({ op = CARG, t = gen.IRT_NIL, ak = ka,
                av = kb, bk = K.KSTR, bv = STROP_CMP[4] })
              outputs = { add({ op = CALLN, t = IRT_INT,
                ak = K.REF, av = c, bk = K.LIT, bv = STR_CMP }) }
            elseif shape == "len" then
              local s = snew(strref(sk, sv, ofs))
              outputs = { add({ op = gen.op_num("FLOAD"), t = IRT_INT,
                ak = K.REF, av = s, bk = K.LIT,
                bv = gen.IRFL_STR_LEN }) }
            else
              -- `s:sub(a, b) == k` / `~= k`. Guarded and
              -- str-typed, as rec_comp emits it.
              local s = snew(strref(sk, sv, ofs))
              local cmp = STROP_CMP[(len == "n" and 4 or len) + 1]
              add({ op = gen.op_num(shape == "eq" and "EQ" or "NE"),
                t = IRT_STR + 0x80, ak = K.REF, av = s,
                bk = K.KSTR, bv = cmp })
              outputs = { i }
            end
            coroutine.yield({ insns = insns, outputs = outputs })
          end
        end
      end
    end
  end)
end

local function count_strops()
  local n = 0
  for _ in iter_strops() do n = n + 1 end
  return n
end

-- -- Buffer-call enumeration
-- -------------------------------------
--
-- COVERAGE ONLY (ljopt models only lj_buf_putstr_reverse of these
-- calls; the rest make the BUFSTR a gap). Split out from
-- iter_buffers so that sweep stays a value oracle.
--
-- `string.format` and `string.rep` record as a CALLL into the
-- buffer, and FOLD constant-evaluates the call when its arguments
-- are constants -- running the real formatter at compile time and
-- replacing the whole call with a BUFPUT of the result. That is
-- bufput_kfold_fmt / bufput_kfold_rep / bufput_kfold_op, none of
-- which any BUFPUT-only chain can reach.
--
-- The format word is an SFormat: type in the low 4 bits, a
-- sub-type at 0x10/0x20/0x30, flags from 0x100 up, and width and
-- precision in bytes 2 and 3 (lj_strfmt.h).
local STRFMT_D, STRFMT_X = 3, 4 + 0x10
local STRFMT_S, STRFMT_C = 6, 7
local STRFMT_G = 5 + 0x30

local BUFCALLS = {
  { call = "lj_strfmt_putfxint", kind = "KINT64", t = "i64",
    sfmts = { STRFMT_D, STRFMT_X, STRFMT_D + (5 * 65536) },
    vals = { 0, 1, -1, 255 } },
  { call = "lj_strfmt_putfstr", kind = "KSTR", t = "str",
    sfmts = { STRFMT_S, STRFMT_S + 0x10 },
    vals = { "", "a", "abc" } },
  { call = "lj_strfmt_putfchar", kind = "KINT", t = "int",
    sfmts = { STRFMT_C }, vals = { 65, 97 } },
  { call = "lj_strfmt_putfnum", kind = "KNUM", t = "num",
    sfmts = { STRFMT_G }, vals = { 0.0, 1.5, -2.25 } },
  { call = "lj_strfmt_putfnum_int", kind = "KNUM", t = "num",
    sfmts = { STRFMT_D }, vals = { 0.0, 3.0 } },
  { call = "lj_strfmt_putfnum_uint", kind = "KNUM", t = "num",
    sfmts = { STRFMT_D }, vals = { 1.0, 7.0 } },
}

-- Two-operand buffer calls: a string argument and nothing else.
local BUFOPS = {
  "lj_buf_putstr_reverse", "lj_buf_putstr_upper",
  "lj_buf_putstr_lower", "lj_strfmt_putquoted",
}

local BUFREP_COUNTS = { 0, 1, 3 }

local function iter_bufcalls(opts)
  opts = opts or {}
  local P32, STR = gen.IRT_P32, gen.IRT_STR
  local BUFHDR, BUFSTR = gen.op_num("BUFHDR"), gen.op_num("BUFSTR")
  local CARG, CALLL = gen.op_num("CARG"), gen.op_num("CALLL")
  local SL = gen.op_num("SLOAD")
  local SLOT = { i64 = gen.IRT_I64, str = STR, int = IRT_INT,
                 num = IRT_NUM }

  -- One case: build the CARG spine for `call`, close the buffer.
  local function emit(call, argk, argv, sf, sym_t)
    local insns = {}
    local function add(x)
      insns[#insns + 1] = x
      return #insns
    end
    local sym
    if sym_t then
      sym = add({ op = SL, t = SLOT[sym_t], ak = K.LIT, av = 1,
        bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
    end
    local h = add({ op = BUFHDR, t = P32, ak = K.KINT, av = 0,
      bk = K.LIT, bv = 0 })
    local spine = h
    if sf then
      spine = add({ op = CARG, t = gen.IRT_NIL, ak = K.REF,
        av = spine, bk = K.KINT, bv = sf })
    end
    if sym then
      spine = add({ op = CARG, t = gen.IRT_NIL, ak = K.REF,
        av = spine, bk = K.REF, bv = sym })
    else
      spine = add({ op = CARG, t = gen.IRT_NIL, ak = K.REF,
        av = spine, bk = argk, bv = argv })
    end
    local cl = add({ op = CALLL, t = P32, ak = K.REF, av = spine,
      bk = K.LIT, bv = gen.ircall_num(call) })
    local out = add({ op = BUFSTR, t = STR, ak = K.REF, av = cl,
      bk = K.REF, bv = h })
    return { insns = insns, outputs = { out } }
  end

  return coroutine.wrap(function()
    for _, c in ipairs(BUFCALLS) do
      for _, sf in ipairs(c.sfmts) do
        for _, v in ipairs(c.vals) do
          -- Constant argument: FOLD runs the formatter now.
          coroutine.yield(emit(c.call, K[c.kind], v, sf, nil))
        end
        -- Loaded argument: the call has to survive to run time.
        coroutine.yield(emit(c.call, K[c.kind], c.vals[1], sf, c.t))
      end
    end
    for _, call in ipairs(BUFOPS) do
      for _, s in ipairs({ "", "aB", "hello" }) do
        coroutine.yield(emit(call, K.KSTR, s, nil, nil))
      end
      coroutine.yield(emit(call, K.KSTR, "x", nil, "str"))
    end
    -- string.rep: CARG(CARG(hdr, str), count).
    for _, s in ipairs({ "", "ab" }) do
      for _, n in ipairs(BUFREP_COUNTS) do
        local insns = {}
        local function add(x)
          insns[#insns + 1] = x
          return #insns
        end
        local h = add({ op = BUFHDR, t = P32, ak = K.KINT, av = 0,
          bk = K.LIT, bv = 0 })
        local c1 = add({ op = CARG, t = gen.IRT_NIL, ak = K.REF,
          av = h, bk = K.KSTR, bv = s })
        local c2 = add({ op = CARG, t = gen.IRT_NIL, ak = K.REF,
          av = c1, bk = K.KINT, bv = n })
        local cl = add({ op = CALLL, t = P32, ak = K.REF, av = c2,
          bk = K.LIT, bv = gen.ircall_num("lj_buf_putstr_rep") })
        local out = add({ op = BUFSTR, t = STR, ak = K.REF,
          av = cl, bk = K.REF, bv = h })
        coroutine.yield({ insns = insns, outputs = { out } })
      end
    end
  end)
end

local function count_bufcalls()
  local n = 0
  for _ in iter_bufcalls() do n = n + 1 end
  return n
end

-- -- Targeted fold-shape enumeration
-- -----------------------------
--
-- What is left in lj_opt_fold.c after the chain enumerations is a
-- long tail of rules keyed on a *shape* the linear chains never
-- build: an op over two constants of the right type, an op over
-- two other ops, or a CONV of a CONV. One rule each, so a table
-- of small named builders beats another cross product.
--
-- Each entry yields one or more traces; `outputs` is whatever the
-- rule's result feeds. Rules over types ljopt cannot compare
-- (i64 divisions, POW, the fp calls) still get replayed -- the
-- driver reports them as gaps rather than findings.
local SHAPE_I64S = { 0, 1, -1, 2, 7, 255, -256 }
local SHAPE_INTS = { 0, 1, -1, 3, 31, 255, -256 }
local SHAPE_NUMS = { 0.0, 1.0, -1.0, 0.5, 2.0, 3.0, -2.5 }

-- Narrowing CONV modes, as (destination type, mode word) pairs.
local SHAPE_NARROW_MODES = {
  { IRT_INT, IRT_INT * 32 + gen.IRT_I64 },
  { IRT_INT, IRT_INT * 32 + gen.IRT_U64 },
  { gen.IRT_U32, gen.IRT_U32 * 32 + gen.IRT_I64 },
  { gen.IRT_U32, gen.IRT_U32 * 32 + gen.IRT_U64 },
}

-- C integer widths a cast can truncate to; `sext` marks the
-- signed ones, which is the bit kfold_conv_kint_ext reads.
local SHAPE_EXT_MODES = {
  IRT_INT * 32 + 15 + 0x800,  -- int.i8 sext
  IRT_INT * 32 + 16,          -- int.u8
  IRT_INT * 32 + 17 + 0x800,  -- int.i16 sext
  IRT_INT * 32 + 18,          -- int.u16
}

local function iter_shapes(opts)
  opts = opts or {}
  local I64, U32, NUM = gen.IRT_I64, gen.IRT_U32, IRT_NUM
  local SL = gen.op_num("SLOAD")
  local CONV, CARG, CALLN = gen.op_num("CONV"), gen.op_num("CARG"),
    gen.op_num("CALLN")
  local I64_INT_SEXT = gen.CONV_I64_INT_SEXT
  local NUM_INT = NUM * 32 + IRT_INT

  -- Build one trace: `body(add, inputs)` returns the output refs.
  local function trace(body)
    local insns = {}
    local function add(x)
      insns[#insns + 1] = x
      return #insns
    end
    local inp = {}
    inp.num = add({ op = SL, t = NUM, ak = K.LIT, av = 1,
      bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
    inp.int = add({ op = SL, t = IRT_INT, ak = K.LIT, av = 2,
      bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
    inp.i64 = add({ op = SL, t = I64, ak = K.LIT, av = 3,
      bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
    inp.int2 = add({ op = SL, t = IRT_INT, ak = K.LIT, av = 4,
      bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
    return { insns = insns, outputs = body(add, inp) }
  end

  return coroutine.wrap(function()
    -- kfold_int64comp / kfold_int64arith / kfold_int64arith2:
    -- both operands constant, so the whole op folds away.
    for _, op in ipairs({ "LT", "GE", "LE", "GT",
                          "ULT", "UGE", "ULE", "UGT", "EQ", "NE" }) do
      for _, a in ipairs(SHAPE_I64S) do
        for _, b in ipairs(SHAPE_I64S) do
          coroutine.yield(trace(function(add, inp)
            add({ op = gen.op_num(op), t = I64 + 0x80,
              ak = K.KINT64, av = a, bk = K.KINT64, bv = b })
            return { inp.int }
          end))
        end
      end
    end
    for _, op in ipairs({ "ADD", "SUB", "MUL", "DIV", "MOD",
                          "BAND", "BOR", "BXOR" }) do
      for _, a in ipairs(SHAPE_I64S) do
        for _, b in ipairs(SHAPE_I64S) do
          coroutine.yield(trace(function(add)
            return { add({ op = gen.op_num(op), t = I64,
              ak = K.KINT64, av = a, bk = K.KINT64, bv = b }) }
          end))
        end
      end
    end
    -- simplify_andor_k64: BAND(BOR(x, k1), k2) and the mirror.
    for _, pair in ipairs({ { "BOR", "BAND" }, { "BAND", "BOR" } }) do
      for _, a in ipairs(SHAPE_I64S) do
        for _, b in ipairs(SHAPE_I64S) do
          coroutine.yield(trace(function(add, inp)
            local inner = add({ op = gen.op_num(pair[1]), t = I64,
              ak = K.REF, av = inp.i64, bk = K.KINT64, bv = a })
            return { add({ op = gen.op_num(pair[2]), t = I64,
              ak = K.REF, av = inner, bk = K.KINT64, bv = b }) }
          end))
        end
      end
    end
    -- simplify_shiftk_andk: a shift of a masked value, where the
    -- mask can be folded through the shift.
    for _, sh in ipairs({ "BSHL", "BSHR", "BSAR", "BROL", "BROR" }) do
      for _, mask in ipairs(SHAPE_INTS) do
        for _, cnt in ipairs({ 0, 1, 4, 8, 31 }) do
          coroutine.yield(trace(function(add, inp)
            local m = add({ op = gen.op_num("BAND"), t = IRT_INT,
              ak = K.REF, av = inp.int, bk = K.KINT, bv = mask })
            return { add({ op = gen.op_num(sh), t = IRT_INT,
              ak = K.REF, av = m, bk = K.KINT, bv = cnt }) }
          end))
        end
      end
    end
    -- simplify_intsubaddadd_cancel: (i+j1) - (i+j2), with the
    -- shared operand in each of the four positions.
    for _, la in ipairs({ 1, 2 }) do
      for _, ra in ipairs({ 1, 2 }) do
        for _, k in ipairs(SHAPE_INTS) do
          coroutine.yield(trace(function(add, inp)
            local function mk(shared_first, kk)
              if shared_first == 1 then
                return add({ op = gen.op_num("ADD"), t = IRT_INT,
                  ak = K.REF, av = inp.int, bk = K.REF,
                  bv = inp.int2 })
              end
              return add({ op = gen.op_num("ADD"), t = IRT_INT,
                ak = K.REF, av = inp.int, bk = K.KINT, bv = kk })
            end
            local l = mk(la, k)
            local r = mk(ra, k + 1)
            return { add({ op = gen.op_num("SUB"), t = IRT_INT,
              ak = K.REF, av = l, bk = K.REF, bv = r }) }
          end))
        end
      end
    end
    -- simplify_conv_narrow: a narrowing CONV pushed through the
    -- arithmetic below it.
    for _, mode in ipairs(SHAPE_NARROW_MODES) do
      for _, op in ipairs({ "ADD", "SUB", "MUL" }) do
        coroutine.yield(trace(function(add, inp)
          local a = add({ op = gen.op_num(op), t = I64, ak = K.REF,
            av = inp.i64, bk = K.KINT64, bv = 3 })
          return { add({ op = CONV, t = mode[1], ak = K.REF,
            av = a, bk = K.LIT, bv = mode[2] }) }
        end))
      end
    end
    -- simplify_conv_int_i64 / simplify_conv_sext: a widening CONV
    -- immediately narrowed again, and the reverse.
    for _, mode in ipairs(SHAPE_NARROW_MODES) do
      coroutine.yield(trace(function(add, inp)
        local w = add({ op = CONV, t = I64, ak = K.REF,
          av = inp.int, bk = K.LIT, bv = I64_INT_SEXT })
        return { add({ op = CONV, t = mode[1], ak = K.REF, av = w,
          bk = K.LIT, bv = mode[2] }) }
      end))
    end
    -- The node type has to match the mode's destination -- that
    -- is the invariant check.lua's CONV lint enforces.
    for _, m in ipairs({ { I64, I64 * 32 + IRT_INT + 0x800 },
                         { gen.IRT_U64,
                           gen.IRT_U64 * 32 + IRT_INT } }) do
      for _, src in ipairs({ "int", "int2" }) do
        coroutine.yield(trace(function(add, inp)
          return { add({ op = CONV, t = m[1], ak = K.REF,
            av = inp[src], bk = K.LIT, bv = m[2] }) }
        end))
      end
    end
    -- kfold_conv_kint_ext: a constant cast to a narrow C type.
    for _, m in ipairs(SHAPE_EXT_MODES) do
      for _, k in ipairs(SHAPE_INTS) do
        coroutine.yield(trace(function(add)
          return { add({ op = CONV, t = IRT_INT, ak = K.KINT,
            av = k, bk = K.LIT, bv = m }) }
        end))
      end
    end
    -- simplify_conv_flt_num: a double rounded to float32 and
    -- back.
    coroutine.yield(trace(function(add, inp)
      local f = add({ op = CONV, t = gen.IRT_FLT, ak = K.REF,
        av = inp.num, bk = K.LIT,
        bv = gen.IRT_FLT * 32 + NUM })
      return { add({ op = CONV, t = NUM, ak = K.REF, av = f,
        bk = K.LIT, bv = NUM * 32 + gen.IRT_FLT }) }
    end))
    -- simplify_tobit_conv: TOBIT of an int widened to num is the
    -- int again.
    for _, src in ipairs({ "int", "int2" }) do
      coroutine.yield(trace(function(add, inp)
        local n = add({ op = CONV, t = NUM, ak = K.REF,
          av = inp[src], bk = K.LIT, bv = NUM_INT })
        return { add({ op = gen.op_num("TOBIT"), t = IRT_INT,
          ak = K.REF, av = n, bk = K.KNUM,
          bv = 6755399441055744 }) }
      end))
    end
    -- simplify_numpow_k / kfold_numpow: the exponent decides
    -- whether POW becomes a multiply chain, a sqrt or nothing.
    for _, k in ipairs({ 0.0, 1.0, 2.0, 3.0, 4.0, -1.0, -2.0,
                         0.5, 2.5, 1e10 }) do
      coroutine.yield(trace(function(add, inp)
        return { add({ op = gen.op_num("POW"), t = NUM, ak = K.REF,
          av = inp.num, bk = K.KNUM, bv = k }) }
      end))
      coroutine.yield(trace(function(add)
        return { add({ op = gen.op_num("POW"), t = NUM,
          ak = K.KNUM, av = 2.0, bk = K.KNUM, bv = k }) }
      end))
    end
    -- kfold_fpcall1 / kfold_fpcall2: a libm call on constants is
    -- evaluated at compile time.
    --
    -- Plain libm entries only. The rule calls ci->func through a
    -- `double (*)(double)` pointer, which is fine for these and a
    -- segfault for the lj_vm_* helpers (lj_vm_floor and friends
    -- are assembler routines with the VM's own argument
    -- convention). x64 records math.floor as FPMATH and never
    -- emits those as a CALLN, so generating one is generator
    -- unsoundness, not a LuaJIT bug.
    for _, call in ipairs({ "sin", "exp", "log", "log10", "atan",
                            "sinh" }) do
      for _, k in ipairs(SHAPE_NUMS) do
        coroutine.yield(trace(function(add)
          return { add({ op = CALLN, t = NUM, ak = K.KNUM, av = k,
            bk = K.LIT, bv = gen.ircall_num(call) }) }
        end))
      end
    end
    for _, a in ipairs(SHAPE_NUMS) do
      for _, b in ipairs(SHAPE_NUMS) do
        coroutine.yield(trace(function(add)
          local c = add({ op = CARG, t = gen.IRT_NIL, ak = K.KNUM,
            av = a, bk = K.KNUM, bv = b })
          return { add({ op = CALLN, t = NUM, ak = K.REF, av = c,
            bk = K.LIT, bv = gen.ircall_num("atan2") }) }
        end))
      end
    end
    -- kfold_add_kgc / kfold_add_kright / kfold_add_kptr, and the
    -- loads off a folded constant pointer (kfold_xload,
    -- xload_kptr, kfold_hload_kkptr). Pointer arithmetic on an
    -- interned string is how STRREF's base is computed, and the
    -- fold turns it into a KKPTR that a second ADD or a load can
    -- then be folded against.
    for _, s in ipairs({ "", "abc" }) do
      for _, k in ipairs({ 0, 1, 3 }) do
        -- No load tail here. kfold_xload / kfold_hload_kkptr
        -- fold a load of a constant pointer by *dereferencing it
        -- at compile time*, so they are only safe on a pointer
        -- the recorder really interned -- feeding them a
        -- synthesized one segfaults the fold engine. The safe
        -- route to kfold_hload_kkptr is `HREF TNEW`, which folds
        -- to the global nil TValue; iter_ahref generates that.
        for _, tail in ipairs({ "none", "add_k", "add_k64",
                                "add_kgc" }) do
          coroutine.yield(trace(function(add)
            -- IRT_PGC, as the recorder emits for a STRREF base.
            local p = add({ op = gen.op_num("ADD"), t = gen.IRT_P32,
              ak = K.KSTR, av = s, bk = K.KINT, bv = k })
            if tail == "add_k" then
              return { add({ op = gen.op_num("ADD"),
                t = gen.IRT_P32, ak = K.REF, av = p,
                bk = K.KINT, bv = 2 }) }
            elseif tail == "add_k64" then
              return { add({ op = gen.op_num("ADD"),
                t = gen.IRT_P32, ak = K.REF, av = p,
                bk = K.KINT64, bv = 2 }) }
            elseif tail == "add_kgc" then
              return { add({ op = gen.op_num("ADD"),
                t = gen.IRT_P32, ak = K.REF, av = p,
                bk = K.KSTR, bv = "z" }) }
            end
            return { p }
          end))
        end
      end
    end
    -- kfold_int64arith's shift cases and simplify_shiftk_andk at
    -- 64-bit width: a masked value shifted by a constant, and a
    -- constant shifted by a constant.
    for _, sh in ipairs({ "BSHL", "BSHR", "BSAR", "BROL", "BROR" }) do
      for _, mask in ipairs(SHAPE_I64S) do
        for _, cnt in ipairs({ 0, 1, 8, 63, 65 }) do
          coroutine.yield(trace(function(add, inp)
            local m = add({ op = gen.op_num("BAND"), t = I64,
              ak = K.REF, av = inp.i64, bk = K.KINT64, bv = mask })
            return { add({ op = gen.op_num(sh), t = I64,
              ak = K.REF, av = m, bk = K.KINT, bv = cnt }) }
          end))
          coroutine.yield(trace(function(add)
            return { add({ op = gen.op_num(sh), t = I64,
              ak = K.KINT64, av = mask, bk = K.KINT, bv = cnt }) }
          end))
        end
      end
    end
    -- kfold_int64comp0: an unsigned compare against zero is
    -- always true and drops out.
    for _, op in ipairs({ "UGE", "ULT", "ULE", "UGT" }) do
      for _, k in ipairs({ 0, 1 }) do
        coroutine.yield(trace(function(add, inp)
          add({ op = gen.op_num(op), t = I64 + 0x80, ak = K.REF,
            av = inp.i64, bk = K.KINT64, bv = k })
          return { inp.int }
        end))
      end
    end
    -- simplify_tobit_conv's u32 case: TOBIT of a u32 widened to
    -- num is just the u32 reinterpreted.
    for _, src in ipairs({ "int", "int2" }) do
      coroutine.yield(trace(function(add, inp)
        local u = add({ op = CONV, t = U32, ak = K.REF,
          av = inp[src], bk = K.LIT, bv = U32 * 32 + IRT_INT })
        local n = add({ op = CONV, t = NUM, ak = K.REF, av = u,
          bk = K.LIT, bv = NUM * 32 + U32 })
        return { add({ op = gen.op_num("TOBIT"), t = IRT_INT,
          ak = K.REF, av = n, bk = K.KNUM,
          bv = 6755399441055744 }) }
      end))
    end
    -- shortcut_left / shortcut_dropleft: abs(abs(x)) and
    -- abs(neg(x)) both collapse to abs(x).
    for _, inner in ipairs({ "ABS", "NEG" }) do
      coroutine.yield(trace(function(add, inp)
        local a = add({ op = gen.op_num(inner), t = NUM,
          ak = K.REF, av = inp.num, bk = K.REF, bv = inp.num })
        return { add({ op = gen.op_num("ABS"), t = NUM, ak = K.REF,
          av = a, bk = K.REF, bv = a }) }
      end))
    end
    -- simplify_intmod_kleft: 0 % x is 0 whatever x is.
    for _, k in ipairs({ 0, 1, -1 }) do
      coroutine.yield(trace(function(add, inp)
        return { add({ op = gen.op_num("MOD"), t = IRT_INT,
          ak = K.KINT, av = k, bk = K.REF, bv = inp.int }) }
      end))
    end
    -- reassoc_minmax_k: (x min k1) min k2 folds the constants.
    for _, op in ipairs({ "MIN", "MAX" }) do
      for _, k1 in ipairs(SHAPE_INTS) do
        for _, k2 in ipairs({ 0, 5, -5 }) do
          coroutine.yield(trace(function(add, inp)
            local m = add({ op = gen.op_num(op), t = IRT_INT,
              ak = K.REF, av = inp.int, bk = K.KINT, bv = k1 })
            return { add({ op = gen.op_num(op), t = IRT_INT,
              ak = K.REF, av = m, bk = K.KINT, bv = k2 }) }
          end))
        end
      end
    end
    -- simplify_floor_conv: floor() of an integer widened to num
    -- is the widening alone.
    for _, fpm in ipairs({ 0, 1, 2 }) do
      coroutine.yield(trace(function(add, inp)
        local n = add({ op = CONV, t = NUM, ak = K.REF,
          av = inp.int, bk = K.LIT, bv = NUM_INT })
        return { add({ op = gen.op_num("FPMATH"), t = NUM,
          ak = K.REF, av = n, bk = K.LIT, bv = fpm }) }
      end))
    end
    -- shortcut_conv_num_int / simplify_conv_i64_num: a round trip
    -- through num collapses.
    for _, m in ipairs({ { IRT_INT, IRT_INT * 32 + IRT_NUM },
                         { I64, I64 * 32 + IRT_NUM },
                         { gen.IRT_U64,
                           gen.IRT_U64 * 32 + IRT_NUM } }) do
      coroutine.yield(trace(function(add, inp)
        local n = add({ op = CONV, t = NUM, ak = K.REF,
          av = inp.int, bk = K.LIT, bv = NUM_INT })
        return { add({ op = CONV, t = m[1], ak = K.REF, av = n,
          bk = K.LIT, bv = m[2] }) }
      end))
    end
    -- kfold_ldexp / kfold_tostr_*: constant-only forms.
    for _, k in ipairs(SHAPE_NUMS) do
      for _, e in ipairs({ 0, 1, -1, 10 }) do
        coroutine.yield(trace(function(add)
          return { add({ op = gen.op_num("LDEXP"), t = NUM,
            ak = K.KNUM, av = k, bk = K.KINT, bv = e }) }
        end))
      end
      coroutine.yield(trace(function(add)
        return { add({ op = gen.op_num("TOSTR"), t = gen.IRT_STR,
          ak = K.KNUM, av = k, bk = K.LIT, bv = 1 }) }
      end))
    end
    for _, k in ipairs(SHAPE_INTS) do
      for _, mode in ipairs({ 0, 2 }) do
        coroutine.yield(trace(function(add)
          return { add({ op = gen.op_num("TOSTR"), t = gen.IRT_STR,
            ak = K.KINT, av = k, bk = K.LIT, bv = mode }) }
        end))
      end
    end
    -- kfold_int64arith2 / kfold_bnot64 / kfold_bswap64: the
    -- 64-bit division, modulo and power of two constants, at both
    -- signednesses -- they take different C helpers -- plus the
    -- two unary 64-bit constant folds.
    for _, op in ipairs({ "DIV", "MOD", "POW" }) do
      for _, t in ipairs({ I64, gen.IRT_U64 }) do
        for _, a in ipairs(SHAPE_I64S) do
          for _, b in ipairs({ 1, 2, 7, -3 }) do
            coroutine.yield(trace(function(add, inp)
              add({ op = gen.op_num(op), t = t, ak = K.KINT64,
                av = a, bk = K.KINT64, bv = b })
              return { inp.int }
            end))
          end
        end
      end
    end
    for _, op in ipairs({ "BNOT", "BSWAP" }) do
      for _, a in ipairs(SHAPE_I64S) do
        coroutine.yield(trace(function(add, inp)
          add({ op = gen.op_num(op), t = I64, ak = K.KINT64,
            av = a, bk = K.NONE, bv = 0 })
          return { inp.int }
        end))
      end
    end
    -- simplify_shift1_ki / simplify_shift2_ki at 64 bits: a
    -- constant shifted by a *variable* count, which is the
    -- operand order the chain enumeration never builds.
    for _, op in ipairs({ "BSHL", "BSHR", "BSAR", "BROL", "BROR" }) do
      for _, a in ipairs({ 0, 1, -1 }) do
        coroutine.yield(trace(function(add, inp)
          return { add({ op = gen.op_num(op), t = I64,
            ak = K.KINT64, av = a, bk = K.REF, bv = inp.int }) }
        end))
      end
    end
    -- The constant conversions: an integer widened to a double at
    -- every source signedness, a 64-bit constant back to a
    -- double, and a double narrowed to 32 and 64 bits unsigned.
    for _, m in ipairs({ NUM * 32 + U32, I64 * 32 + IRT_INT,
                         gen.IRT_U64 * 32 + IRT_INT,
                         I64 * 32 + U32,
                         gen.IRT_U64 * 32 + U32 }) do
      for _, k in ipairs(SHAPE_INTS) do
        coroutine.yield(trace(function(add, inp)
          add({ op = CONV, t = m >= I64 * 32 and I64 or NUM,
            ak = K.KINT, av = k, bk = K.LIT, bv = m })
          return { inp.int }
        end))
      end
    end
    for _, m in ipairs({ NUM * 32 + I64, NUM * 32 + gen.IRT_U64 }) do
      for _, k in ipairs(SHAPE_I64S) do
        coroutine.yield(trace(function(add, inp)
          add({ op = CONV, t = NUM, ak = K.KINT64, av = k,
            bk = K.LIT, bv = m })
          return { inp.int }
        end))
      end
    end
    for _, m in ipairs({ { U32, U32 * 32 + NUM },
                         { I64, gen.IRT_U64 * 32 + NUM } }) do
      for _, k in ipairs({ 0.0, 1.0, -1.0, 2.5, 1e10, -3.5 }) do
        coroutine.yield(trace(function(add, inp)
          add({ op = CONV, t = m[1], ak = K.KNUM, av = k,
            bk = K.LIT, bv = m[2] })
          return { inp.int }
        end))
      end
    end
    -- The CONV-of-CONV shortcuts: a value converted out and back
    -- collapses, and a narrowing CONV of a widening one is a
    -- single CONV -- or nothing at all.
    local CONV_PAIRS = {
      -- num <- int <- num, and its int <- num <- int mirror.
      { "num", NUM * 32 + IRT_INT, NUM, IRT_INT * 32 + NUM, IRT_INT },
      { "int", IRT_INT * 32 + NUM, IRT_INT, NUM * 32 + IRT_INT, NUM },
      -- i64 <- int <- num: narrowing feeding a widening CONV.
      { "num", IRT_INT * 32 + NUM, IRT_INT, I64 * 32 + IRT_INT + 0x800,
        I64 },
      { "num", U32 * 32 + NUM, U32, I64 * 32 + U32, I64 },
      -- int <- i64 <- int, and the u32 variants of the same.
      { "int", I64 * 32 + IRT_INT + 0x800, I64, IRT_INT * 32 + I64,
        IRT_INT },
      { "int", I64 * 32 + IRT_INT + 0x800, I64, U32 * 32 + I64, U32 },
      -- float <- num <- float: the only 32-bit fp round trip.
      { "num", gen.IRT_FLT * 32 + NUM, gen.IRT_FLT,
        NUM * 32 + gen.IRT_FLT, NUM },
      -- num <- i64 <- num, both signednesses.
      { "num", I64 * 32 + NUM, I64, NUM * 32 + I64, NUM },
      { "num", gen.IRT_U64 * 32 + NUM, gen.IRT_U64,
        NUM * 32 + gen.IRT_U64, NUM },
    }
    for _, c in ipairs(CONV_PAIRS) do
      coroutine.yield(trace(function(add, inp)
        local mid = add({ op = CONV, t = c[3], ak = K.REF,
          av = inp[c[1]], bk = K.LIT, bv = c[2] })
        return { add({ op = CONV, t = c[5], ak = K.REF, av = mid,
          bk = K.LIT, bv = c[4] }) }
      end))
    end
    -- simplify_floor_conv: rounding an integer that was just
    -- widened to a double is a no-op.
    for _, m in ipairs(gen.FPMATH_MODES) do
      coroutine.yield(trace(function(add, inp)
        local n = add({ op = CONV, t = NUM, ak = K.REF,
          av = inp.int, bk = K.LIT, bv = NUM_INT })
        return { add({ op = gen.op_num("FPMATH"), t = NUM,
          ak = K.REF, av = n, bk = K.LIT, bv = m }) }
      end))
    end
    -- shortcut_left / shortcut_dropleft: abs(abs(x)) and
    -- abs(-x) both collapse to abs(x).
    for _, inner in ipairs({ "ABS", "NEG" }) do
      coroutine.yield(trace(function(add, inp)
        local a = add({ op = gen.op_num(inner), t = NUM,
          ak = K.REF, av = inp.num, bk = K.REF, bv = inp.num })
        return { add({ op = gen.op_num("ABS"), t = NUM,
          ak = K.REF, av = a, bk = K.REF, bv = a }) }
      end))
    end
    -- simplify_intsubaddadd_cancel: (i + j1) - (i + j2) and its
    -- three operand orders all cancel the shared term.
    for _, ord in ipairs({ { 1, 1 }, { 1, 2 }, { 2, 1 }, { 2, 2 } }) do
      coroutine.yield(trace(function(add, inp)
        local shared, other = inp.int, inp.int2
        local l = ord[1] == 1
          and { shared, other } or { other, shared }
        local r = ord[2] == 1
          and { shared, other } or { other, shared }
        local a = add({ op = gen.op_num("ADD"), t = IRT_INT,
          ak = K.REF, av = l[1], bk = K.REF, bv = l[2] })
        local b = add({ op = gen.op_num("ADD"), t = IRT_INT,
          ak = K.REF, av = r[1], bk = K.KINT, bv = 3 })
        if ord[2] == 2 then
          b = add({ op = gen.op_num("ADD"), t = IRT_INT,
            ak = K.KINT, av = 3, bk = K.REF, bv = r[1] })
        end
        return { add({ op = gen.op_num("SUB"), t = IRT_INT,
          ak = K.REF, av = a, bk = K.REF, bv = b }) }
      end))
    end
    -- reassoc_bxor: xor with the same value twice cancels, and
    -- reassoc_minmax_k folds two constant bounds into one.
    coroutine.yield(trace(function(add, inp)
      local x = add({ op = gen.op_num("BXOR"), t = IRT_INT,
        ak = K.REF, av = inp.int, bk = K.REF, bv = inp.int2 })
      return { add({ op = gen.op_num("BXOR"), t = IRT_INT,
        ak = K.REF, av = x, bk = K.REF, bv = inp.int2 }) }
    end))
    for _, op in ipairs({ "MIN", "MAX" }) do
      for _, k in ipairs({ { 3, 7 }, { 7, 3 }, { -1, -1 } }) do
        coroutine.yield(trace(function(add, inp)
          local m = add({ op = gen.op_num(op), t = IRT_INT,
            ak = K.REF, av = inp.int, bk = K.KINT, bv = k[1] })
          return { add({ op = gen.op_num(op), t = IRT_INT,
            ak = K.REF, av = m, bk = K.KINT, bv = k[2] }) }
        end))
      end
    end
    -- kfold_intop's modulo case: two constants, which is the one
    -- integer MOD the recorder can leave behind after narrowing.
    for _, a in ipairs(SHAPE_INTS) do
      for _, b in ipairs({ 1, 3, -3, 7 }) do
        coroutine.yield(trace(function(add)
          return { add({ op = gen.op_num("MOD"), t = IRT_INT,
            ak = K.KINT, av = a, bk = K.KINT, bv = b }) }
        end))
      end
    end
    -- The other half of the CONV-of-CONV rules: the ones that
    -- *decline*. Each needs the outer rule's pattern to match with
    -- an inner source type it cannot use, so the pairs below are
    -- deliberately mismatched.
    local CONV_DECLINE = {
      -- num <- int over a *guarded* int <- num: the only shape
      -- shortcut_conv_num_int accepts.
      { NUM * 32 + IRT_INT, NUM, IRT_INT * 32 + NUM, IRT_INT + 0x80,
        "num" },
      -- int <- num over num <- i64: source is i64, not int.
      { IRT_INT * 32 + NUM, IRT_INT, NUM * 32 + I64, NUM, "i64" },
      -- i64 <- num over num <- u32, and over num <- i64.
      { I64 * 32 + NUM, I64, NUM * 32 + U32, NUM, "int" },
      { I64 * 32 + NUM, I64, NUM * 32 + I64, NUM, "i64" },
      -- int <- i64 over i64 <- num: source is num, not int/u32.
      { IRT_INT * 32 + I64, IRT_INT, I64 * 32 + NUM, I64, "num" },
    }
    for _, c in ipairs(CONV_DECLINE) do
      coroutine.yield(trace(function(add, inp)
        local mid = add({ op = CONV, t = c[4], ak = K.REF,
          av = inp[c[5]], bk = K.LIT, bv = c[3] })
        return { add({ op = CONV, t = c[2], ak = K.REF, av = mid,
          bk = K.LIT, bv = c[1] }) }
      end))
    end
    -- simplify_conv_flt_num needs a value that already came
    -- *from* a float, so the round trip has to be three deep.
    coroutine.yield(trace(function(add, inp)
      local f = add({ op = CONV, t = gen.IRT_FLT, ak = K.REF,
        av = inp.num, bk = K.LIT,
        bv = gen.IRT_FLT * 32 + NUM })
      local n = add({ op = CONV, t = NUM, ak = K.REF, av = f,
        bk = K.LIT, bv = NUM * 32 + gen.IRT_FLT })
      return { add({ op = CONV, t = gen.IRT_FLT, ak = K.REF,
        av = n, bk = K.LIT, bv = gen.IRT_FLT * 32 + NUM }) }
    end))
    -- simplify_tobit_conv / simplify_floor_conv over the source
    -- types they accept (u32) and one they do not (i64).
    for _, src in ipairs({ U32, I64 }) do
      coroutine.yield(trace(function(add, inp)
        local n = add({ op = CONV, t = NUM, ak = K.REF,
          av = src == U32 and inp.int or inp.i64,
          bk = K.LIT, bv = NUM * 32 + src })
        return { add({ op = gen.op_num("TOBIT"), t = IRT_INT,
          ak = K.REF, av = n, bk = K.KNUM,
          bv = 6755399441055744 }) }
      end))
      for _, m in ipairs(gen.FPMATH_MODES) do
        coroutine.yield(trace(function(add, inp)
          local n = add({ op = CONV, t = NUM, ak = K.REF,
            av = src == U32 and inp.int or inp.i64,
            bk = K.LIT, bv = NUM * 32 + src })
          return { add({ op = gen.op_num("FPMATH"), t = NUM,
            ak = K.REF, av = n, bk = K.LIT, bv = m }) }
        end))
      end
    end
    -- shortcut_left / shortcut_dropleft: ABS and NEG carry the
    -- sign mask in op2, and the rules are keyed on that operand
    -- being an FLOAD -- which is what lj_ir_ksimd emits. A
    -- tab.asize FLOAD stands in for it: the rules only look at
    -- the opcode.
    for _, inner in ipairs({ "ABS", "NEG" }) do
      coroutine.yield(trace(function(add, inp)
        local tab = add({ op = SL, t = gen.IRT_TAB, ak = K.LIT,
          av = 5, bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
        local mask = add({ op = gen.op_num("FLOAD"), t = IRT_INT,
          ak = K.REF, av = tab, bk = K.LIT, bv = 8 })
        local a = add({ op = gen.op_num(inner), t = NUM,
          ak = K.REF, av = inp.num, bk = K.REF, bv = mask })
        return { add({ op = gen.op_num("ABS"), t = NUM,
          ak = K.REF, av = a, bk = K.REF, bv = mask }) }
      end))
    end
    -- simplify_intsubaddadd_cancel's last case, (j1 + i) - (j2 +
    -- i): the shared term has to be the *lower* ref so
    -- commutativity canonicalization leaves it on the right of
    -- both adds.
    coroutine.yield(trace(function(add, inp)
      local j1 = add({ op = gen.op_num("MUL"), t = IRT_INT,
        ak = K.REF, av = inp.int2, bk = K.KINT, bv = 3 })
      local j2 = add({ op = gen.op_num("MUL"), t = IRT_INT,
        ak = K.REF, av = inp.int2, bk = K.KINT, bv = 5 })
      local a = add({ op = gen.op_num("ADD"), t = IRT_INT,
        ak = K.REF, av = j1, bk = K.REF, bv = inp.int })
      local b = add({ op = gen.op_num("ADD"), t = IRT_INT,
        ak = K.REF, av = j2, bk = K.REF, bv = inp.int })
      return { add({ op = gen.op_num("SUB"), t = IRT_INT,
        ak = K.REF, av = a, bk = K.REF, bv = b }) }
    end))
    -- kfold_hload_kkptr: an HREF of a fresh table with no
    -- matching key folds to the global nil TValue, and the load
    -- off it has to be eliminated here -- neither forwarding nor
    -- the backend can do it.
    for _, key in ipairs({ 1, 7 }) do
      coroutine.yield(trace(function(add, inp)
        local tn = add({ op = gen.op_num("TNEW"),
          t = gen.IRT_TAB + 0x80, ak = K.LIT, av = 4,
          bk = K.LIT, bv = 0 })
        local h = add({ op = gen.op_num("HREF"), t = gen.IRT_P32,
          ak = K.REF, av = tn, bk = K.KINT, bv = key })
        add({ op = gen.op_num("HLOAD"), t = NUM + 0x80,
          ak = K.REF, av = h, bk = K.NONE, bv = 0 })
        return { inp.int }
      end))
    end
    -- barrier_tnew_tdup keeps the barrier of a table allocated
    -- before the loop: the allocation is old by then, so it may
    -- have survived a GC step. Only a loop replay reaches it.
    coroutine.yield(trace(function(add, inp)
      local tn = add({ op = gen.op_num("TNEW"),
        t = gen.IRT_TAB + 0x80, ak = K.LIT, av = 4,
        bk = K.LIT, bv = 0 })
      add({ op = gen.op_num("TBAR"), t = gen.IRT_NIL,
        ak = K.REF, av = tn, bk = K.NONE, bv = 0 })
      return { inp.int }
    end))
    -- prof: two neighbouring PROF markers collapse into one.
    coroutine.yield(trace(function(add, inp)
      add({ op = gen.op_num("PROF"), t = gen.IRT_NIL,
        ak = K.NONE, av = 0, bk = K.NONE, bv = 0 })
      add({ op = gen.op_num("PROF"), t = gen.IRT_NIL,
        ak = K.NONE, av = 0, bk = K.NONE, bv = 0 })
      return { inp.int }
    end))
  end)
end

local function count_shapes()
  local n = 0
  for _ in iter_shapes() do n = n + 1 end
  return n
end

-- -- FFI pointer-arithmetic enumeration
-- ---------------------------
--
-- iter_xmem stores and loads at fixed pointers, which reaches
-- aa_xref's type rules but none of the address arithmetic. A real
-- `a[i]` on an FFI array records as
--
--   i64 BSHL  i     +2        -- index << log2(elemsize)
--   p64 ADD   bshl  base
--   p64 ADD   add   +8        -- past the cdata header
--   int XLOAD add
--
-- and `a[i+1]` in the same loop body reuses that first address
-- plus a constant: reassoc_xref() recognizes the
-- `BSHL(ADD(i, k), sh)` spine and rewrites the second access into
-- an offset off the first, but only once J->chain[IR_LOOP] is set
-- -- so these shapes only do their job under COV_LOOP.
--
-- CNEW bases are here too: aa_cnew()/aa_findcnew() disambiguate
-- two pointers by walking back to the allocation each came from,
-- and only an allocation made inside the trace can be found.
local XREF_WIDTHS = {
  { name = "u8", t = 16, shift = 0, size = 1 },
  { name = "i16", t = 17, shift = 1, size = 2 },
  { name = "int", t = IRT_INT, shift = 2, size = 4 },
  { name = "i64", t = 21, shift = 3, size = 8 },
  { name = "num", t = IRT_NUM, shift = 3, size = 8 },
}

local XREF_BASES = { "sload", "cnew", "cnew2" }

local XREF_SHAPES = {
  "load_next",   -- a[i] then a[i+1]: the reassociation shape
  "load_same",   -- a[i] twice: plain CSE
  "load_ofs",    -- a[i] and the same address at another offset
  "store_load",  -- a[i] = v; read it back
  "store_next",  -- a[i] = v; read a[i+1]
  "dse",         -- two stores to one address, then a load
  "fref",        -- FREF/FSTORE/FLOAD on the cdata payload field
  "fref_two",    -- two field stores, then a load of the first
}

local FIELD_CDATA_PTR = 15
local FIELD_CDATA_INT64 = 18

local function iter_xref(opts)
  opts = opts or {}
  local CDT, P64, I64 = gen.IRT_CDT, gen.IRT_P64, gen.IRT_I64
  local SL, ADD, BSHL = gen.op_num("SLOAD"), gen.op_num("ADD"),
    gen.op_num("BSHL")
  local XLOAD, XSTORE = gen.op_num("XLOAD"), gen.op_num("XSTORE")
  local HDR = 8  -- cdata payload starts past the header

  return coroutine.wrap(function()
    for _, w in ipairs(XREF_WIDTHS) do
      for _, basekind in ipairs(XREF_BASES) do
        for _, shape in ipairs(XREF_SHAPES) do
          local insns = {}
          local function add(x)
            insns[#insns + 1] = x
            return #insns
          end
          local i = add({ op = SL, t = IRT_INT, ak = K.LIT, av = 1,
            bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
          local sz = add({ op = SL, t = I64, ak = K.LIT, av = 2,
            bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
          -- Values of the element type, so a wrong store is
          -- visible in the load.
          local v1 = add({ op = SL, t = w.t, ak = K.LIT, av = 3,
            bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
          local v2 = add({ op = SL, t = w.t, ak = K.LIT, av = 4,
            bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
          local function cnew()
            -- Sized form (`ffi.new("T[?]", n)`), so op2 is a real
            -- ref; the recorder's TREF_NIL has no operand kind.
            return add({ op = gen.op_num("CNEW"), t = CDT + 0x80,
              ak = K.KINT, av = 21, bk = K.REF, bv = sz })
          end
          local base, base2
          if basekind == "sload" then
            base = add({ op = SL, t = CDT, ak = K.LIT, av = 5,
              bk = K.LIT, bv = gen.SLOAD_TYPECHECK })
            base2 = base
          else
            base = cnew()
            base2 = basekind == "cnew2" and cnew() or base
          end
          -- base + (idx << shift) + HDR + extra
          local function addr(b, idx_ref, extra)
            local p = idx_ref
            if w.shift > 0 then
              p = add({ op = BSHL, t = I64, ak = K.REF,
                av = idx_ref, bk = K.KINT, bv = w.shift })
            end
            p = add({ op = ADD, t = P64, ak = K.REF, av = p,
              bk = K.REF, bv = b })
            return add({ op = ADD, t = P64, ak = K.REF, av = p,
              bk = K.KINT, bv = HDR + (extra or 0) })
          end
          local function next_idx()
            return add({ op = ADD, t = IRT_INT, ak = K.REF, av = i,
              bk = K.KINT, bv = 1 })
          end
          local function xload(p)
            return add({ op = XLOAD, t = w.t, ak = K.REF, av = p,
              bk = K.LIT, bv = 0 })
          end
          local function xstore(p, v)
            add({ op = XSTORE, t = w.t, ak = K.REF, av = p,
              bk = K.REF, bv = v })
          end
          local function fref(b, field)
            return add({ op = gen.op_num("FREF"), t = P64,
              ak = K.REF, av = b, bk = K.LIT, bv = field })
          end

          local outputs
          if shape == "load_same" then
            outputs = { xload(addr(base, i)), xload(addr(base2, i)) }
          elseif shape == "load_ofs" then
            outputs = { xload(addr(base, i)),
                        xload(addr(base2, i, w.size)) }
          elseif shape == "store_load" then
            local p = addr(base, i)
            xstore(p, v1)
            outputs = { xload(addr(base2, i)) }
          elseif shape == "store_next" then
            xstore(addr(base, i), v1)
            outputs = { xload(addr(base2, next_idx())) }
          elseif shape == "dse" then
            local p = addr(base, i)
            xstore(p, v1)
            xstore(addr(base2, i), v2)
            outputs = { xload(p) }
          elseif shape == "fref" then
            local f = fref(base, FIELD_CDATA_INT64)
            add({ op = gen.op_num("FSTORE"), t = I64, ak = K.REF,
              av = f, bk = K.REF, bv = sz })
            outputs = { add({ op = gen.op_num("FLOAD"), t = I64,
              ak = K.REF, av = base2, bk = K.LIT,
              bv = FIELD_CDATA_INT64 }) }
          elseif shape == "fref_two" then
            local f1 = fref(base, FIELD_CDATA_INT64)
            local f2 = fref(base2, FIELD_CDATA_PTR)
            add({ op = gen.op_num("FSTORE"), t = I64, ak = K.REF,
              av = f1, bk = K.REF, bv = sz })
            add({ op = gen.op_num("FSTORE"), t = P64, ak = K.REF,
              av = f2, bk = K.REF, bv = base })
            outputs = { add({ op = gen.op_num("FLOAD"), t = I64,
              ak = K.REF, av = base, bk = K.LIT,
              bv = FIELD_CDATA_INT64 }) }
          else
            outputs = { xload(addr(base, i)),
                        xload(addr(base2, next_idx())) }
          end
          coroutine.yield({ insns = insns, outputs = outputs })
        end
      end
    end
  end)
end

local function count_xref()
  local n = 0
  for _ in iter_xref() do n = n + 1 end
  return n
end

return {
  iter = iter,
  count = count,
  iter_strings = iter_strings,
  count_strings = count_strings,
  iter_alias = iter_alias,
  count_alias = count_alias,
  iter_xmem = iter_xmem,
  count_xmem = count_xmem,
  iter_mixed = iter_mixed,
  count_mixed = count_mixed,
  iter_guard = iter_guard,
  count_guard = count_guard,
  iter_narrow = iter_narrow,
  count_narrow = count_narrow,
  iter_sink = iter_sink,
  count_sink = count_sink,
  iter_buffers = iter_buffers,
  count_buffers = count_buffers,
  iter_abc = iter_abc,
  count_abc = count_abc,
  iter_upval = iter_upval,
  count_upval = count_upval,
  iter_ahref = iter_ahref,
  count_ahref = count_ahref,
  iter_strops = iter_strops,
  count_strops = count_strops,
  iter_bufcalls = iter_bufcalls,
  count_bufcalls = count_bufcalls,
  iter_shapes = iter_shapes,
  count_shapes = count_shapes,
  iter_xref = iter_xref,
  count_xref = count_xref,
  leaves_for = leaves_for,
  OPS = OPS,
}
