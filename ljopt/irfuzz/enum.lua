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
    -- lj_opt_narrow for Lua-level `+`/`-`/`*` that stayed integer.
    -- Guards: the overflow test is the trace exit.
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
  -- prologue_for); constants are KINT64. Only ops ljopt models for
  -- i64 AND the recorder emits via FFI 64-bit arithmetic/bitwise:
  -- ADD/SUB/MUL/BAND/BOR/BXOR plus the shifts. Shifts run through
  -- BinOpShiftI64 (count masked & 63, full 64-bit width) -- the
  -- i64 sibling of the int shift-mask fix. Excluded: DIV/MOD
  -- (recorder lowers 64-bit div/mod to CALL helpers, no IR_DIV),
  -- NEG/BSWAP (no ljopt I64 translator).
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
    -- the bias KNUM (lj_ir_knum_tobit = 0x4338000000000000), which
    -- ljopt ignores -- it models the op directly as RNE fp->int.
    -- Reaches LJFOLD(TOBIT KNUM KNUM) and the TOBIT ADD/SUB/CONV
    -- simplifications.
    { to = IRT_INT, op = "TOBIT", bk = K.KNUM,
      mode = 6755399441055744 },
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
                -- store_at/load_at take a *precomputed* element ref
                -- so a shape can control instruction ordering (DSE
                -- needs the two stores adjacent -- see below).
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
  leaves_for = leaves_for,
  OPS = OPS,
}
