-- Deterministic random IR-trace generator for the ljopt fuzzer.
--
-- Produces a synthetic, typed SSA-IR instruction stream that
-- stays within the recorder-plausible subset ljopt can
-- translate: SLOAD inputs, KINT/KNUM constants, and pure
-- binary arithmetic / bitwise ops. No guards, memory ops,
-- allocations or calls (see the plan's phasing). The stream
-- is handed to jit.util.irfuzz(), which replays it through
-- the fold engine at -O0 and -O3.
--
-- Everything is a pure function of the integer seed: a
-- local LCG is used instead of math.random so results are
-- identical across Lua builds (project rule: no
-- nondeterminism).

local vmdef = require("jit.vmdef")

-- IR types (indexes into irtype_text / IRT enum).
local IRT_NUM = 14
local IRT_INT = 19
local IRT_I64 = 21
local IRT_TAB = 11   -- table pointer
-- 32-bit GC pointer (AREF/HREF/FLOAD tab.array result)
local IRT_P32 = 5
-- Raw-memory (FFI) types. Narrow C integers only ever reach the
-- IR through XLOAD/XSTORE -- LuaJIT promotes them to int for any
-- arithmetic -- so these exist purely for the xmem enumerator.
local IRT_I8, IRT_U8, IRT_I16, IRT_U16 = 15, 16, 17, 18
local IRT_U32, IRT_U64 = 20, 22
local IRT_FLT = 13
local IRT_CDT = 10
local IRT_P64 = 9

-- Operand kinds -- must match the IRFUZZ_OPND_* enum in
-- lib_jit.c.
local K_NONE, K_REF, K_KINT, K_KNUM, K_LIT, K_KINT64 = 0, 1, 2, 3, 4, 5

-- CONV mode literal (op2) for int -> i64 sign-extend: the
-- recorder's own way of widening a Lua-number int to i64
-- (lj_opt_narrow.c: (IRT_I64<<IRCONV_DSH)|IRT_INT|IRCONV_SEXT).
-- IRCONV_DSH = 5, IRCONV_SEXT = 0x800.
local CONV_I64_INT_SEXT = (IRT_I64 * 32) + IRT_INT + 0x800

-- SLOAD flags: TYPECHECK (a plain typed slot read).
local SLOAD_TYPECHECK = 4

-- FLOAD field literal (op2), from jit.vmdef.irfield indices.
local FIELD_TAB_ARRAY = 6

-- Array indices (AREF) and hash keys (HREF) MUST come from
-- disjoint value ranges. LuaJIT keeps a table's array part
-- and hash part in separate address spaces, and the
-- recorder only ever reaches a given key through one of
-- them; ljopt models both as make_tab_ref(tab,key), so if
-- the same key value were used for an array element AND a
-- hash slot they would alias in the SMT (a spurious
-- store->load conflict => false sat). Positive ints go to
-- the array part, negative ints to the hash part, so the
-- two never overlap.
local ARR_IDXS = { 1, 2, 3, 4, 5 }
local HASH_KEYS = { -1, -2, -3, -7 }

-- Resolve an IR opcode name to its numeric opcode via
-- vmdef.irnames (a packed table of 6-char names).
local irop_num = setmetatable({}, {
  __index = function(t, name)
    local names = vmdef.irnames
    for i = 0, math.floor(#names / 6) - 1 do
      local entry = names:sub(6 * i + 1, 6 * i + 6):gsub("%s+$", "")
      if entry == name then
        t[name] = i
        return i
      end
    end
    error("gen: unknown IR opcode " .. name)
  end,
})

-- Op selection is BLACKLIST-based, not whitelist-based: we
-- generate the full set of binary arith/bitwise ops the
-- recorder can emit for each type, then remove only
-- entries we can justify removing. A whitelist would only
-- ever exercise ops ljopt already models, so it could
-- never surface a *new* gap or miscompile; the blacklist
-- keeps generation broad and forces every exclusion to be
-- documented.
--
-- Two exclusion reasons, kept separate on purpose:
--
--  RECORDER_IMPOSSIBLE -- op+type the JIT recorder never
--    emits, so feeding it would be generator unsoundness (a
--    false finding about IR that can't occur), not a real
--    bug. Derived from LuaJIT's emit sites, e.g.
--    lj_opt_narrow_mod only emits IR_MOD for integers
--    (IRTI); float `a % b` lowers to a-floor(a/b)*b, so
--    `num MOD` never occurs. int DIV/MOD are lowered away
--    on x64 (see the u32-ops-reachability memory).
--
--  KNOWN_LJOPT_GAP -- op ljopt models incompletely
--    (uninterpreted / missing fold identity), so it yields
--    spurious sat we've already triaged. Excluded by
--    default (opts.exclude_gaps ~= false) to keep LuaJIT-bug
--    hunting clean, but re-includable to hunt more ljopt
--    gaps. e.g. POW: uninterpreted pow_fp vs LuaJIT's
--    x^2->x*x fold. See the irfuzz-pow-model-gap memory.
local ALL_NUM_OPS = {
  "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "MIN", "MAX", "FPMATH",
  -- Unary FP arith (NEG/ABS) and LDEXP (x * 2^n). All are IRTN
  -- in the recorder (lj_ffrecord/lj_opt_narrow emit sites).
  "NEG", "ABS", "LDEXP",
}

-- FPMATH is unary (value + IRFPM mode literal). Only the
-- interpreted rounding modes are generated; floor=0 ceil=1
-- trunc=2 sqrt=3. The transcendental modes
-- (log/log2/sin/cos/exp) are ljopt-NYI and would decode to
-- gap nodes -- see FPMATH.lua is_implemented.
local FPMATH_MODES = { 0, 1, 2, 3 }
local ALL_INT_OPS = {
  "ADD", "SUB", "MUL", "DIV", "MOD",
  "BAND", "BOR", "BXOR", "BSHL", "BSHR", "BSAR", "BROL", "BROR",
  -- Unary int arith: NEG (2's-complement negate), BNOT (~x),
  -- BSWAP (byte reverse). All IRTI in the recorder.
  "NEG", "BNOT", "BSWAP",
}

-- Unary ops: op1 is the sole value operand. NEG/ABS carry
-- an op2=ref in the IR (the SSE sign-mask ksimd for FP),
-- which ljopt ignores, so we mirror op1 into op2 --
-- LuaJIT's int crecord does the same
-- (`emitir(IRTI(IR_NEG), x, x)`). BNOT/BSWAP have op2 mode
-- `___` (no op2), so op2 must be absent.
local UNARY_OPS = { NEG = true, ABS = true, BNOT = true, BSWAP = true }
local UNARY_NO_OP2 = { BNOT = true, BSWAP = true }

-- LDEXP exponent: op2 is a `num` (lj_ir_tonum on x64), but only
-- integer values are meaningful (LuaJIT truncates). Keep it
-- a small integer-valued constant so the encoding stays exact.
local LDEXP_EXPS = { 0.0, 1.0, 2.0, 3.0, -1.0, -2.0, 10.0, -10.0 }

local RECORDER_IMPOSSIBLE = {
  [IRT_NUM] = { MOD = true },
  [IRT_INT] = { DIV = true, MOD = true },
}
local KNOWN_LJOPT_GAP = {
  [IRT_NUM] = { POW = true },
  -- BSHL/BSHR/BSAR are fixed (count masked & 31, BSHR now
  -- logical) -- see irfuzz-shift-mask-gap. BROL/BROR are now
  -- enabled too: ext_rotate_left/_right are defined in the SMT
  -- preamble (smt_constants.lua) and BROL's int result is
  -- sign-extended like every other int op.
  [IRT_INT] = {},
}

local function menu_for(t, exclude_gaps)
  local all = (t == IRT_NUM) and ALL_NUM_OPS or ALL_INT_OPS
  local out = {}
  for _, op in ipairs(all) do
    local blocked = RECORDER_IMPOSSIBLE[t][op]
      or (exclude_gaps and KNOWN_LJOPT_GAP[t][op])
    if not blocked then out[#out + 1] = op end
  end
  return out
end

-- Minimal reproducible PRNG (SplitMix-ish LCG over 2^32).
local function rng_new(seed)
  local state = (seed * 2654435761) % 2 ^ 32
  return function(n)
    state = (state * 1103515245 + 12345) % 2 ^ 32
    local r = math.floor(state / 65536)
    if n then return (r % n) + 1 end
    return r
  end
end

-- The constants LuaJIT's fold rules hard-code, so that every
-- constant-triggered arithmetic optimization actually fires. A
-- fold rule that special-cases `x + 0.0` is only exercised if the
-- fuzzer emits `+ 0.0`, so we embed the exact literals from
-- lj_opt_fold.c rather than sampling "interesting" values.
--
-- num (lj_opt_fold.c simplify_num*, simplify_pow):
--   0.0 / -0.0  x -+ 0        (fold.c:1008-1019)
--   1.0         x o 1 -> x    (1037)
--   -1.0        x * -1 -> -x  (1039)
--   2.0         x * 2 -> x+x; x^2 -> x*x (1045, 1090)
--   0.5 0.25 4.0 8.0  x / 2^k -> x * (1/2^k) reciprocal (1050-1055)
-- 3.14 / 1e308 are deliberately NON-special (a generic value and
-- an overflow-prone one) so we also cover the "no fold" paths.
local NUM_CONSTS = {
  0.0, -0.0, 1.0, -1.0, 2.0, 0.5, 0.25, 4.0, 8.0, 3.14, 1e308,
}
-- int (lj_opt_fold.c simplify_int*, simplify_band/bor/bxor/shift):
--   0            identity/absorbing for +,-,*,band,bor,bxor,shift
--   1            i*1->i; i<<1->i+i           (1319, 1578)
--   2 4 8 16     i*2->i+i; i*2^k->i<<k; i%2^k->i&(2^k-1) (1321,1380,1413)
--   -1           i&-1->i; i|-1->-1; i xor -1 -> ~i        (1531-1559)
--   3 7 15 31 63 masks 2^k-1 for i%2^k -> i & mask         (1413)
--   31 32 33 63 64  shift-count boundaries (count masked & 31/& 63,
--                fold.c:275/380/1814 -- the x<<33 == x<<1 case)
--   0x7fffffff / -0x80000000  int max/min (overflow boundaries)
local INT_CONSTS = {
  0, 1, -1, 2, 4, 8, 16, 3, 7, 15, 31, 32, 33, 63, 64,
  0x7fffffff, -0x80000000,
}
-- i64 (lj_opt_fold.c KINT64 rules: ADD/SUB/MUL/BAND/BOR/BXOR
-- KINT64 KINT64 at 393-398, reassoc ADD/MUL/BAND/BOR/BXOR . KINT64
-- at 1748-1752). Same identity/absorbing triggers as int, plus one
-- value past 2^31 to exercise genuinely-64-bit arithmetic (not just
-- the sign-extended int range). All are exactly representable as a
-- double, which is how the harness marshals a KINT64 operand.
local I64_CONSTS = {
  0, 1, -1, 2, 4, 8, 3, 7, 4294967296,
  -- 65 is a shift count > 63: 65 & 63 = 1, distinct from the raw
  -- value, so it exercises the BinOpShiftI64 count mask (x << 65
  -- must equal x << 1, which SMT bvshl-by-65 = 0 would get wrong).
  65,
}

-- Numeric opcodes for the ops roots() must recognise: SLOAD
-- inputs and the stores produce no comparable value.
local SLOAD_OP = irop_num.SLOAD
local STORE_OP_NUM = {
  [irop_num.ASTORE] = true, [irop_num.HSTORE] = true,
  [irop_num.FSTORE] = true, [irop_num.XSTORE] = true,
}

-- The roots of a trace's dataflow: every computed value-typed
-- result that no later instruction consumes as an operand. These
-- are the only observable values, so they are the ones the two
-- traces must agree on. In `a=b+c; d=a+c; e=d+d` only `e` is a
-- root -- `a` and `d` are dead intermediates. The optimizer is
-- free to restructure how a root is computed (CSE, reassoc,
-- folding intermediates away), so asserting equality on a consumed
-- intermediate would over-constrain it and could flag a legal
-- transform as a miscompile. This mirrors a real snapshot, which
-- captures live stack slots, not dead temporaries. SLOAD inputs
-- (tied to shared pre-trace memory) and stores (no value) never
-- qualify. Shared by the random (gen) and exhaustive (enum) paths.
local function roots(insns)
  local consumed = {}
  for _, ins in ipairs(insns) do
    if ins.ak == K_REF then consumed[ins.av] = true end
    if ins.bk == K_REF then consumed[ins.bv] = true end
  end
  local out = {}
  for i, ins in ipairs(insns) do
    if (ins.t == IRT_NUM or ins.t == IRT_INT)
      and ins.op ~= SLOAD_OP and not STORE_OP_NUM[ins.op]
      and not consumed[i]
    then
      out[#out + 1] = i
    end
  end
  return out
end

-- Generate an instruction stream from a seed.
--
-- @seed    integer seed.
-- @opts    optional { insns=<count>, inputs=<#SLOAD>,
--          ints=<bool> }.
-- Returns  insns (array of { op, t, ak, av, bk, bv }) and outputs
--          (array of 1-based stream refs whose values are
--          compared).
local function gen(seed, opts)
  opts = opts or {}
  local rand = rng_new(seed)
  local ninputs = opts.inputs or 3
  local nbody = opts.insns or 12
  local use_ints = opts.ints ~= false
  local exclude_gaps = opts.exclude_gaps ~= false
  local menu = {
    [IRT_NUM] = menu_for(IRT_NUM, exclude_gaps),
    [IRT_INT] = menu_for(IRT_INT, exclude_gaps),
  }

  local insns = {}
  -- Typed pools of available stream refs (1-based
  -- instruction index).
  local pool = { [IRT_NUM] = {}, [IRT_INT] = {} }

  -- Stores are typed by their value operand (e.g. `num ASTORE`)
  -- but produce NO usable value, so they must never enter the
  -- value pool.
  local STORE_OPS = { ASTORE = true, HSTORE = true,
                      FSTORE = true, XSTORE = true }

  local function emit(op, t, ak, av, bk, bv)
    insns[#insns + 1] = { op = irop_num[op], t = t, ak = ak, av = av,
                          bk = bk, bv = bv }
    -- Only value-typed results feed later arithmetic operand
    -- picks; table/pointer refs (tab, p32) and stores are
    -- tracked elsewhere.
    if pool[t] and not STORE_OPS[op] then table.insert(pool[t], #insns) end
    return #insns
  end

  -- Seed inputs: typed SLOADs on distinct stack slots. op1 is the
  -- slot literal, op2 is the SLOAD flags literal.
  local types = use_ints and { IRT_NUM, IRT_INT } or { IRT_NUM }
  for slot = 1, ninputs do
    local t = types[rand(#types)]
    emit("SLOAD", t, K_LIT, slot, K_LIT, SLOAD_TYPECHECK)
  end

  -- Pick a random typed operand: an existing ref, or a constant.
  local function operand(t)
    local refs = pool[t]
    -- ~40% constant, else a live ref (fall back to constant
    -- early on).
    if #refs == 0 or rand(5) <= 2 then
      if t == IRT_NUM then
        return K_KNUM, NUM_CONSTS[rand(#NUM_CONSTS)]
      else
        return K_KINT, INT_CONSTS[rand(#INT_CONSTS)]
      end
    end
    return K_REF, refs[rand(#refs)]
  end

  -- -- Table / array support ----------------------------------
  -- Tables are seeded as extra `SLOAD tab` inputs on their
  -- own stack slots (tied to shared pre-trace memory by
  -- ljopt's MemoryStack).
  -- A table op emits a recorder-shaped access chain:
  -- array: FLOAD tab tab.array -> AREF base idx -> ALOAD | ASTORE
  -- hash:  HREF tab key                         -> HLOAD | HSTORE
  -- A load pushes its num result into the value pool, so a stored
  -- value can be read back and flow into later arithmetic;
  -- the opt pass forwards store->load while unopt re-reads
  -- memory, which is exactly the equivalence the oracle
  -- checks.
  local use_tables = opts.tables == true
  local tables = {}   -- { { tab = <ssa>, arr = <ssa|nil> }, ... }
  local next_tab_slot = ninputs

  local function new_table()
    next_tab_slot = next_tab_slot + 1
    local tref = emit("SLOAD", IRT_TAB, K_LIT, next_tab_slot,
      K_LIT, SLOAD_TYPECHECK)
    local entry = { tab = tref }
    tables[#tables + 1] = entry
    return entry
  end

  local function array_base(entry)
    if not entry.arr then
      entry.arr = emit("FLOAD", IRT_P32, K_REF, entry.tab,
        K_LIT, FIELD_TAB_ARRAY)
    end
    return entry.arr
  end

  local function emit_table_op()
    local entry = tables[rand(#tables)]
    if rand(2) == 1 then
      -- Array access: element ref then load or store a num.
      local base = array_base(entry)
      -- Loads carry IRT_GUARD (+0x80): every ALOAD/HLOAD the
      -- recorder emits is a guard (a type check on the loaded
      -- value) -- verified by -jdump, both when forwarding is off
      -- and for a non-forwardable key; a same-key load under -O3
      -- is not "unguarded", it is forwarded away entirely.
      -- Emitting them unguarded produced recorder-impossible IR:
      -- lj_opt_dse_ahstore bails on an intervening guard, so with
      -- plain loads DSE deleted stores across a load and the opt
      -- trace then read a different value -- the source of the
      -- --tables false SATs (seeds 104/329/867/872).
      local ref = emit("AREF", IRT_P32, K_REF, base,
        K_KINT, ARR_IDXS[rand(#ARR_IDXS)])
      if rand(2) == 1 then
        local vk, vv = operand(IRT_NUM)
        emit("ASTORE", IRT_NUM, K_REF, ref, vk, vv)
      else
        emit("ALOAD", IRT_NUM + 0x80, K_REF, ref, K_NONE, 0)
      end
    else
      -- Hash access on a small numeric key.
      local ref = emit("HREF", IRT_P32, K_REF, entry.tab,
        K_KINT, HASH_KEYS[rand(#HASH_KEYS)])
      if rand(2) == 1 then
        local vk, vv = operand(IRT_NUM)
        emit("HSTORE", IRT_NUM, K_REF, ref, vk, vv)
      else
        emit("HLOAD", IRT_NUM + 0x80, K_REF, ref, K_NONE, 0)
      end
    end
  end

  if use_tables then new_table() end

  for _ = 1, nbody do
    -- ~1 in 3 body slots is a table access (when tables are
    -- enabled).
    if use_tables and rand(3) == 1 then
      if #tables < 3 and rand(4) == 1 then new_table() end
      emit_table_op()
      goto continue
    end
    local t = types[rand(#types)]
    local ops = menu[t]
    local op = ops[rand(#ops)]
    if op == "FPMATH" then
      -- Unary: op1 = num value, op2 = IRFPM mode literal.
      local ak, av = operand(IRT_NUM)
      emit("FPMATH", IRT_NUM, ak, av, K_LIT, FPMATH_MODES[rand(#FPMATH_MODES)])
    elseif op == "LDEXP" then
      -- x * 2^n: op1 = num value, op2 = num (integer-valued)
      -- exponent.
      local ak, av = operand(IRT_NUM)
      emit("LDEXP", IRT_NUM, ak, av, K_KNUM, LDEXP_EXPS[rand(#LDEXP_EXPS)])
    elseif UNARY_OPS[op] then
      local ak, av = operand(t)
      if UNARY_NO_OP2[op] then
        emit(op, t, ak, av, K_NONE, 0)
      else
        emit(op, t, ak, av, ak, av)
      end
    else
      local ak, av = operand(t)
      local bk, bv = operand(t)
      emit(op, t, ak, av, bk, bv)
    end
    ::continue::
  end

  -- Outputs: the roots of the dataflow (see roots()).
  return insns, roots(insns)
end

-- Pack an instruction stream into the flat spec table
-- jit.util.irfuzz expects: parallel arrays indexed 1..n.
-- `outputs` (optional) lists the stream indexes the replay must
-- keep live: the post-fold passes read liveness out of a snapshot
-- over them, so everything else is dead and DCE can act.
local function to_spec(insns, outputs)
  local spec = { n = #insns, op = {}, t = {},
                 ak = {}, av = {}, bk = {}, bv = {}, out = outputs }
  for i = 1, #insns do
    local ins = insns[i]
    spec.op[i] = ins.op
    spec.t[i] = ins.t
    spec.ak[i] = ins.ak
    spec.av[i] = ins.av
    spec.bk[i] = ins.bk
    spec.bv[i] = ins.bv
  end
  return spec
end

return {
  gen = gen,
  to_spec = to_spec,
  roots = roots,
  menu_for = menu_for,
  op_num = function(name) return irop_num[name] end,
  IRT_NUM = IRT_NUM,
  IRT_INT = IRT_INT,
  IRT_I64 = IRT_I64,
  NUM_CONSTS = NUM_CONSTS,
  INT_CONSTS = INT_CONSTS,
  I64_CONSTS = I64_CONSTS,
  CONV_I64_INT_SEXT = CONV_I64_INT_SEXT,
  FPMATH_MODES = FPMATH_MODES,
  LDEXP_EXPS = LDEXP_EXPS,
  UNARY_OPS = UNARY_OPS,
  UNARY_NO_OP2 = UNARY_NO_OP2,
  -- Operand kinds (mirror the IRFUZZ_OPND_* enum in lib_jit.c).
  kinds = { NONE = 0, REF = 1, KINT = 2, KNUM = 3, LIT = 4, KINT64 = 5,
            KSTR = 6 },
  -- Small constant string pool for string-op fuzzing. Kept short
  -- and varied in length so `#s` folds produce distinct constants;
  -- z3 String reasoning is costly, so string shapes stay minimal.
  STR_CONSTS = { "", "a", "hi", "abc", "hello", "lorem ipsum" },
  IRFL_STR_LEN = 0,
  -- Shift/rotate counts for 64-bit shifts (emitted as KINT, the
  -- width the recorder uses: LJFOLD(BSHL KINT64 KINT)). Spans the
  -- mask boundary: 32/63 are in range, 65 exceeds it (65 & 63 = 1)
  -- so the count mask is exercised.
  SHIFT_COUNTS = { 0, 1, 7, 31, 32, 63, 65 },
  SLOAD_TYPECHECK = SLOAD_TYPECHECK,
  -- Table/memory access building blocks, used by the aliasing
  -- enumerator in enum.lua.
  IRT_TAB = IRT_TAB,
  IRT_P32 = IRT_P32,
  FIELD_TAB_ARRAY = FIELD_TAB_ARRAY,
  ARR_IDXS = ARR_IDXS,
  HASH_KEYS = HASH_KEYS,
  -- Raw FFI memory building blocks, used by the xmem enumerator.
  IRT_I8 = IRT_I8,
  IRT_U8 = IRT_U8,
  IRT_I16 = IRT_I16,
  IRT_U16 = IRT_U16,
  IRT_U32 = IRT_U32,
  IRT_U64 = IRT_U64,
  IRT_FLT = IRT_FLT,
  IRT_CDT = IRT_CDT,
  IRT_P64 = IRT_P64,
}
