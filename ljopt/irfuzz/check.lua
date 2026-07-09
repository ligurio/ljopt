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
local function attach_snapshot(rec, pass, cmp)
  local slots = {}
  for i, g in ipairs(cmp) do
    local ref = pass.map[g]
    local slot = i - 1
    if ref > 0 then
      slots[#slots + 1] = { slot, { type = "ssa", value = ref } }
    else
      slots[#slots + 1] = { slot, {
        type = "const",
        value = decode.const_smt_bv(pass, ref),
        const_type = "number",
      } }
    end
  end
  -- snap_id 1, taken after the last instruction; no guards
  -- => no exits.
  rec.snapshots = { [1] = { nins = { #rec.trace + 1 }, slots = slots } }
end

-- Classify an output ref on one side: nil if comparable, else
-- the op name that makes it a gap (dummy/NYI or uninterpreted).
local function gap_op(trace, nyi, ref)
  if ref < 0 then return nil end
  if nyi[ref] then return trace.trace[ref].irop end
  local op = trace.trace[ref].irop
  if UNINTERPRETED[op] then return op end
  return nil
end

-- Build the full SMT query for one seed. Returns the intermediate
-- artifacts so callers (driver, tests) can inspect traces and
-- formula.
local function build(seed, opts)
  opts = opts or {}
  local insns, outputs = gen.gen(seed, opts)

  -- Replay through the fold engine twice (unopt + opt).
  local unopt_pass, opt_pass = jutil.irfuzz(gen.to_spec(insns))
  local trace_u = decode.decode(unopt_pass)
  local trace_o = decode.decode(opt_pass)

  -- An output is comparable only if it is usable on BOTH sides. A
  -- dummy/uninterpreted output is reported as a coverage gap
  -- instead (ljopt's snapshot path would silently skip a NYI
  -- slot anyway; classifying keeps broad blacklist generation
  -- from going blind).
  local nyi_u = ir_nodes.get_nyi_nodes(trace_u.trace)
  local nyi_o = ir_nodes.get_nyi_nodes(trace_o.trace)
  local cmp, gaps = {}, {}
  for _, g in ipairs(outputs) do
    local bad = gap_op(trace_u, nyi_u, unopt_pass.map[g])
      or gap_op(trace_o, nyi_o, opt_pass.map[g])
    if bad then
      gaps[#gaps + 1] = { genref = g, op = bad }
    else
      cmp[#cmp + 1] = g
    end
  end

  local formula, skipped = nil, (#cmp == 0)
  if not skipped then
    attach_snapshot(trace_u, unopt_pass, cmp)
    attach_snapshot(trace_o, opt_pass, cmp)
    -- One synthetic trace pair, keyed identically on both sides.
    local smt = ir_smtlib.compare_trace_records({ trace_u }, { trace_o })
    formula = PREAMBLE .. smt[1] .. "\n(check-sat)\n"
  end

  return {
    seed = seed,
    skipped = skipped,
    gaps = gaps,
    insns = insns,
    outputs = outputs,
    cmp_outputs = cmp,
    trace_unopt = trace_u,
    trace_opt = trace_o,
    formula = formula,
  }
end

-- Human-readable render of a decoded trace (one line per
-- instruction), in the style of luajit -jdump's IR view.
local function render_trace(trace)
  local out = {}
  for i, n in ipairs(trace.trace) do
    out[#out + 1] = ("%04d %s%-6s %-6s %-16s %s"):format(
      i, n.flags.raw or "  ", n.irtype, n.irop,
      n.op1_txt or "", n.op2_txt or "")
  end
  return table.concat(out, "\n")
end

return {
  build = build,
  render_trace = render_trace,
}
