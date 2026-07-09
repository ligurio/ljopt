-- Deterministic random IR-trace generator for the ljopt fuzzer.
--
-- Produces a synthetic, typed SSA-IR instruction stream that stays
-- within the recorder-plausible subset ljopt can translate: SLOAD
-- inputs, KINT/KNUM constants, and pure binary arithmetic / bitwise
-- ops. No guards, memory ops, allocations or calls (see the plan's
-- phasing). The stream is handed to jit.util.irfuzz(), which replays
-- it through the fold engine at -O0 and -O3.
--
-- Everything is a pure function of the integer seed: a local LCG is
-- used instead of math.random so results are identical across Lua
-- builds (project rule: no nondeterminism).

local vmdef = require("jit.vmdef")

-- IR types (indexes into irtype_text / IRT enum).
local IRT_NUM = 14
local IRT_INT = 19

-- Operand kinds -- must match the IRFUZZ_OPND_* enum in lib_jit.c.
local K_NONE, K_REF, K_KINT, K_KNUM, K_LIT = 0, 1, 2, 3, 4

-- SLOAD flags: TYPECHECK (a plain typed slot read).
local SLOAD_TYPECHECK = 4

-- Resolve an IR opcode name to its numeric opcode via vmdef.irnames
-- (a packed table of 6-char names).
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

-- Op selection is BLACKLIST-based, not whitelist-based: we generate
-- the full set of binary arith/bitwise ops the recorder can emit for
-- each type, then remove only entries we can justify removing. A
-- whitelist would only ever exercise ops ljopt already models, so it
-- could never surface a *new* gap or miscompile; the blacklist keeps
-- generation broad and forces every exclusion to be documented.
--
-- Two exclusion reasons, kept separate on purpose:
--
--  RECORDER_IMPOSSIBLE -- op+type the JIT recorder never emits, so
--    feeding it would be generator unsoundness (a false finding about
--    IR that can't occur), not a real bug. Derived from LuaJIT's emit
--    sites, e.g. lj_opt_narrow_mod only emits IR_MOD for integers
--    (IRTI); float `a % b` lowers to a-floor(a/b)*b, so `num MOD`
--    never occurs. int DIV/MOD are lowered away on x64 (see the
--    u32-ops-reachability memory).
--
--  KNOWN_LJOPT_GAP -- op ljopt models incompletely (uninterpreted /
--    missing fold identity), so it yields spurious sat we've already
--    triaged. Excluded by default (opts.exclude_gaps ~= false) to keep
--    LuaJIT-bug hunting clean, but re-includable to hunt more ljopt
--    gaps. e.g. POW: uninterpreted pow_fp vs LuaJIT's x^2->x*x fold.
--    See the irfuzz-pow-model-gap memory.
local ALL_NUM_OPS = {
  "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "MIN", "MAX", "FPMATH",
  -- Unary FP arith (NEG/ABS) and LDEXP (x * 2^n). All are IRTN in the
  -- recorder (lj_ffrecord/lj_opt_narrow emit sites).
  "NEG", "ABS", "LDEXP",
}

-- FPMATH is unary (value + IRFPM mode literal). Only the interpreted
-- rounding modes are generated; floor=0 ceil=1 trunc=2 sqrt=3. The
-- transcendental modes (log/log2/sin/cos/exp) are ljopt-NYI and would
-- decode to gap nodes -- see FPMATH.lua is_implemented.
local FPMATH_MODES = { 0, 1, 2, 3 }
local ALL_INT_OPS = {
  "ADD", "SUB", "MUL", "DIV", "MOD",
  "BAND", "BOR", "BXOR", "BSHL", "BSHR", "BSAR", "BROL", "BROR",
  -- Unary int arith: NEG (2's-complement negate), BNOT (~x), BSWAP
  -- (byte reverse). All IRTI in the recorder.
  "NEG", "BNOT", "BSWAP",
}

-- Unary ops: op1 is the sole value operand. NEG/ABS carry an op2=ref
-- in the IR (the SSE sign-mask ksimd for FP), which ljopt ignores, so
-- we mirror op1 into op2 -- LuaJIT's int crecord does the same
-- (`emitir(IRTI(IR_NEG), x, x)`). BNOT/BSWAP have op2 mode `___` (no
-- op2), so op2 must be absent.
local UNARY_OPS = { NEG = true, ABS = true, BNOT = true, BSWAP = true }
local UNARY_NO_OP2 = { BNOT = true, BSWAP = true }

-- LDEXP exponent: op2 is a `num` (lj_ir_tonum on x64), but only
-- integer values are meaningful (LuaJIT truncates). Keep it a small
-- integer-valued constant so the encoding stays exact.
local LDEXP_EXPS = { 0.0, 1.0, 2.0, 3.0, -1.0, -2.0, 10.0, -10.0 }

local RECORDER_IMPOSSIBLE = {
  [IRT_NUM] = { MOD = true },
  [IRT_INT] = { DIV = true, MOD = true },
}
local KNOWN_LJOPT_GAP = {
  [IRT_NUM] = { POW = true },
  -- BSHL/BSHR/BSAR are fixed (count masked & 31, BSHR now logical) --
  -- see irfuzz-shift-mask-gap. Rotates stay excluded: ext_rotate_left/
  -- _right are not defined in the SMT preamble, so BROL/BROR need
  -- separate verification before enabling.
  [IRT_INT] = { BROL = true, BROR = true },
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

-- A few "interesting" numeric constants fold rules care about.
local NUM_CONSTS = { 0.0, 1.0, -1.0, 2.0, 0.5, -0.0, 3.14, 1e308 }
local INT_CONSTS = { 0, 1, -1, 2, 7, 31, 32, 0x7fffffff, -0x80000000 }

-- Generate an instruction stream from a seed.
--
-- @seed    integer seed.
-- @opts    optional { insns=<count>, inputs=<#SLOAD>, ints=<bool> }.
-- Returns  insns (array of { op, t, ak, av, bk, bv }) and outputs
--          (array of 1-based stream refs whose values are compared).
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
  -- Typed pools of available stream refs (1-based instruction index).
  local pool = { [IRT_NUM] = {}, [IRT_INT] = {} }

  local function emit(op, t, ak, av, bk, bv)
    insns[#insns + 1] = { op = irop_num[op], t = t, ak = ak, av = av,
                          bk = bk, bv = bv }
    table.insert(pool[t], #insns)
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
    -- ~40% constant, else a live ref (fall back to constant early on).
    if #refs == 0 or rand(5) <= 2 then
      if t == IRT_NUM then
        return K_KNUM, NUM_CONSTS[rand(#NUM_CONSTS)]
      else
        return K_KINT, INT_CONSTS[rand(#INT_CONSTS)]
      end
    end
    return K_REF, refs[rand(#refs)]
  end

  for _ = 1, nbody do
    local t = types[rand(#types)]
    local ops = menu[t]
    local op = ops[rand(#ops)]
    if op == "FPMATH" then
      -- Unary: op1 = num value, op2 = IRFPM mode literal.
      local ak, av = operand(IRT_NUM)
      emit("FPMATH", IRT_NUM, ak, av, K_LIT, FPMATH_MODES[rand(#FPMATH_MODES)])
    elseif op == "LDEXP" then
      -- x * 2^n: op1 = num value, op2 = num (integer-valued) exponent.
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
  end

  -- Outputs: the last live ref of each type (what we prove equal).
  local outputs = {}
  for _, t in ipairs(types) do
    local refs = pool[t]
    if #refs > 0 then outputs[#outputs + 1] = refs[#refs] end
  end

  return insns, outputs
end

-- Pack an instruction stream into the flat spec table jit.util.irfuzz
-- expects: parallel arrays indexed 1..n.
local function to_spec(insns)
  local spec = { n = #insns, op = {}, t = {},
                 ak = {}, av = {}, bk = {}, bv = {} }
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
  IRT_NUM = IRT_NUM,
  IRT_INT = IRT_INT,
}
