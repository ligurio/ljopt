-- Glue: generate a synthetic IR trace, replay it through the fold
-- engine at -O0 and -O3 via jit.util.irfuzz, then hand two
-- trace_records (each with a final snapshot over the outputs) to
-- ljopt's existing equivalence path. UNSAT => the optimizer
-- preserved observable state; SAT => a candidate miscompile (or
-- an ljopt modelling gap -- see triage).
--
-- This module contains NO SMT: equivalence is computed entirely
-- by ljopt.ir_smtlib.compare_trace_records, the same code the
-- recorded path uses. We only build recorded-shaped trace_records
-- (trace + snapshots) and classify outputs the oracle can't
-- reason about.

local jutil = require("jit.util")
local gen = require("ljopt.irfuzz.gen")
local decode = require("ljopt.irfuzz.decode")
local ir_smtlib = require("ljopt.ir_smtlib")
local ir_nodes = require("ljopt.ir.ir_nodes")
local smt_constants = require("ljopt.smt_constants")

-- Modeled on the SMT side but uninterpreted (z3 can't relate
-- them to a folded/interpreted form), so comparing them is
-- unsound as a bug oracle. Reported as coverage gaps. Keep in
-- sync with ljopt/ir/*.lua.
local UNINTERPRETED = { POW = true }

-- The SMT preamble translate_to_smt uses for each standalone
-- query.
local PREAMBLE = [[
(set-option :print-success false)
(set-option :produce-models true)
]] .. smt_constants.LJOPT_SMTLIB

-- Attach a single final snapshot to a decoded trace_record,
-- capturing the given comparable outputs into stack slots
-- 0..k-1. Slot i holds output cmp[i]; the same assignment is
-- used on both sides so ljopt's snapshot comparison pairs them.
-- `pass.map[g]` is the decoded ref: > 0 is an SSA node
-- (snapshot references it and ljopt reads its typed value),
-- < 0 is a folded constant (materialized in the snapshot).
local function attach_snapshot(rec, pass, cmp, loop)
  local slots = {}
  for i, g in ipairs(cmp) do
    local ref = pass.map[g]
    -- A loop replay writes its outputs back into the slots the
    -- SLOADs read (slot 1 up), which is how the unroller pairs a
    -- body result with its input and infers the PHI.
    local slot = loop and i or (i - 1)
    if ref > 0 then
      slots[#slots + 1] = { slot, { type = "ssa", value = ref } }
    else
      local bv, const_type = decode.const_smt_bv(pass, ref)
      slots[#slots + 1] = { slot, {
        type = "const",
        value = bv,
        const_type = const_type,
      } }
    end
  end
  -- Two snapshots. Snapshot 1 sits before the whole stream so
  -- enrich_snapshots_with_exits (which attaches a guard to the
  -- snapshot with nins <= ir_id) assigns every guard in the
  -- trace to it -- that is what feeds `snap_<name>_te` and makes
  -- guard elimination visible to the equivalence check. It holds
  -- no slots: it only owns exits. Snapshot 2 sits after the last
  -- instruction and carries the compared output values.
  rec.snapshots = {
    [1] = { nins = { 1 }, slots = {} },
    [2] = { nins = { #rec.trace + 1 }, slots = slots,
            last_slots = slots },
  }
end

-- Classify an output ref on one side: nil if comparable, else
-- the op name that makes it a gap (dummy/NYI or uninterpreted).
local function gap_op(trace, nyi, pass, ref)
  if ref < 0 then
    -- A folded GC/pointer constant (HREF on a fresh table folds
    -- to the global nil slot, for one) has no bitvector encoding,
    -- so it cannot go into a snapshot slot. Report the gap
    -- instead of letting const_smt_bv assert.
    local k = pass.kval[-ref]
    local t = type(k)
    if t ~= "number" and t ~= "cdata" and t ~= "string" then
      return "K" .. t
    end
    return nil
  end
  if nyi[ref] then return trace.trace[ref].irop end
  local op = trace.trace[ref].irop
  if UNINTERPRETED[op] then return op end
  return nil
end

-- Human-readable render of a decoded trace (one line per
-- instruction), in the style of luajit -jdump's IR view. Constants
-- render as exact 64-bit hex (float_to_smt_bv), so two traces with
-- equal renders translate to identical SMT.
local function render_trace(trace)
  local out = {}
  for i, n in ipairs(trace.trace) do
    out[#out + 1] = ("%04d %s%-6s %-6s %-16s %s"):format(
      i, n.flags.raw or "  ", n.irtype, n.irop,
      n.op1_txt or "", n.op2_txt or "")
  end
  return table.concat(out, "\n")
end

-- Serialize a record's final-snapshot slot assignments, for the
-- same equality comparison.
local function snap_txt(rec)
  local parts = {}
  for _, s in ipairs(rec.snapshots[1].slots) do
    local v = s[2]
    parts[#parts + 1] = ("%d=%s:%s"):format(s[1], v.type, tostring(v.value))
  end
  return table.concat(parts, ";")
end

-- Ops whose ljopt SMT encoding is provably commutative (fp.add /
-- fp.mul under one rounding mode, and the bitwise int ops), so a
-- pure operand swap cannot change the result. NOT MIN/MAX: SMT
-- fp.min/fp.max are underspecified on (+0,-0), so operand order
-- there must go to z3. Used to render a trace with these ops'
-- operands sorted: if BOTH traces normalize to the same text, the
-- opt trace differs only by swaps of these ops and is equivalent
-- by commutativity alone -- z3 spends ~30s re-proving exactly
-- that, so the driver may skip it.
local COMMUT_SMT = {
  ADD = true, MUL = true, BAND = true, BOR = true, BXOR = true,
}
local function render_commut_norm(trace)
  local out = {}
  for i, n in ipairs(trace.trace) do
    local a, b = n.op1_txt or "", n.op2_txt or ""
    if COMMUT_SMT[n.irop] and b < a then a, b = b, a end
    out[#out + 1] = ("%04d %s%-6s %-6s %-16s %s"):format(
      i, n.flags.raw or "  ", n.irtype, n.irop, a, b)
  end
  return table.concat(out, "\n")
end

-- Build the full SMT query for one seed. Returns the intermediate
-- artifacts so callers (driver, tests) can inspect traces and
-- formula.
-- Build the SMT query from an explicit instruction stream and its
-- output (root) refs. Shared by the random path (build, via
-- gen.gen) and the exhaustive path (enum). `seed` is only carried
-- through for reporting and may be nil.
-- Well-formedness lint: a CONV's node type must equal its mode's
-- destination type. LuaJIT's fold engine maintains this invariant
-- ("fold: keep type of emitted CONV in sync with its mode",
-- c9588f51, the fix for LuaJIT#524) -- the buggy fold emitted
-- int-typed CONVs with u32 modes. The *semantic* damage of that
-- lie happens below ljopt's abstraction (the backend elides
-- sign/zero-extension moves based on the type field), so the
-- SMT equivalence check cannot see it: ljopt keys CONV
-- semantics on the mode string, which stayed correct. The lint
-- convicts the malformed instruction directly instead.
local function lint_conv_types(rec)
  local bad = {}
  for i, ins in ipairs(rec.trace) do
    if ins.irop == "CONV" and ins.op2_txt and ins.irtype then
      local dest = ins.op2_txt:match("^(%w+)%.")
      if dest and dest ~= ins.irtype then
        bad[#bad + 1] = ("%04d %s CONV %s"):format(
          i, ins.irtype, ins.op2_txt)
      end
    end
  end
  return bad
end

local function build_from(insns, outputs, opts, seed)
  opts = opts or {}

  -- Replay through the fold engine twice (unopt + opt).
  --
  -- A guard whose condition folds to statically false makes
  -- LuaJIT abort with the trace error LJ_TRERR_GFAIL ("guard
  -- would always fail"), thrown from C as a bare number. That is
  -- not a finding: the recorder only ever emits a guard in the
  -- direction that held at record time (rec_comp /
  -- rec_comp_fixup), so a statically-false guard is
  -- recorder-impossible. Report it as an aborted trace and let
  -- the driver skip it. Non-numeric errors are real, so they
  -- are re-raised.
  -- A loop replay runs lj_opt_loop, so the optimized trace gets a
  -- LOOP marker and PHIs while the unoptimized one stays straight;
  -- ljopt unrolls each shape once it knows the link is a loop.
  local spec = gen.to_spec(insns, outputs)
  spec.loop = opts.loop or nil
  local replay_ok, unopt_pass, opt_pass = pcall(jutil.irfuzz, spec)
  if not replay_ok then
    local err = unopt_pass
    if type(err) ~= "number" then error(err, 0) end
    return {
      seed = seed, skipped = true, trace_err = err,
      identical = false, commut_only = false, gaps = {},
      insns = insns, outputs = outputs, cmp_outputs = {},
    }
  end
  local linktype = opts.loop and "loop" or nil
  local trace_u = decode.decode(unopt_pass, linktype)
  local trace_o = decode.decode(opt_pass, linktype)
  local lint = lint_conv_types(trace_o)
  local lint_u = lint_conv_types(trace_u)
  for _, x in ipairs(lint_u) do lint[#lint + 1] = x .. " (unopt)" end

  -- An output is comparable only if it is usable on BOTH sides. A
  -- dummy/uninterpreted output is reported as a coverage gap
  -- instead (ljopt's snapshot path would silently skip a NYI
  -- slot anyway; classifying keeps broad blacklist generation
  -- from going blind).
  local nyi_u = ir_nodes.get_nyi_nodes(trace_u.trace)
  local nyi_o = ir_nodes.get_nyi_nodes(trace_o.trace)
  local cmp, gaps = {}, {}
  for _, g in ipairs(outputs) do
    local bad = gap_op(trace_u, nyi_u, unopt_pass, unopt_pass.map[g])
      or gap_op(trace_o, nyi_o, opt_pass, opt_pass.map[g])
    if bad then
      gaps[#gaps + 1] = { genref = g, op = bad }
    else
      cmp[#cmp + 1] = g
    end
  end

  local formula, identical, commut_only = nil, false, false
  local skipped = (#cmp == 0)
  if not skipped then
    attach_snapshot(trace_u, unopt_pass, cmp, opts.loop)
    attach_snapshot(trace_o, opt_pass, cmp, opts.loop)
    -- The optimized pass changed nothing: both traces render (and
    -- thus translate) identically, so equivalence is trivially
    -- unsat and a driver may skip z3. Exact because constants
    -- render as full-precision hex.
    identical = render_trace(trace_u) == render_trace(trace_o)
      and snap_txt(trace_u) == snap_txt(trace_o)
    -- Weaker but still sound: identical after sorting the
    -- operands of provably-commutative ops (fold canonicalizes
    -- `k + x` to `x + k`), see render_commut_norm.
    commut_only = not identical
      and render_commut_norm(trace_u) == render_commut_norm(trace_o)
      and snap_txt(trace_u) == snap_txt(trace_o)
    -- One synthetic trace pair, keyed identically on both sides.
    local smt = ir_smtlib.compare_trace_records({ trace_u }, { trace_o })
    formula = PREAMBLE .. smt[1] .. "\n(check-sat)\n"
  end

  return {
    seed = seed,
    skipped = skipped,
    identical = identical,
    commut_only = commut_only,
    gaps = gaps,
    insns = insns,
    outputs = outputs,
    cmp_outputs = cmp,
    trace_unopt = trace_u,
    trace_opt = trace_o,
    lint = lint,
    formula = formula,
  }
end

-- Random path: derive the instruction stream from a seed, then run
-- the shared pipeline.
local function build(seed, opts)
  local insns, outputs = gen.gen(seed, opts or {})
  return build_from(insns, outputs, opts, seed)
end

return {
  build = build,
  build_from = build_from,
  render_trace = render_trace,
}
