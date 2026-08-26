-- Driver for the ljopt IR-optimizer fuzzer.
--
-- Usage:
--   luajit ljopt/irfuzz/fuzz.lua --show SEED
--       Dump the unopt trace, opt trace and both SMT
--       formulas for one seed (the artifacts the
--       equivalence check is built from).
--
--   luajit ljopt/irfuzz/fuzz.lua
--       [--seed S] [--count N] [--insns K]
--       Generate N traces starting at seed S, check
--       each with z3, and report any SAT (candidate
--       miscompile) with its seed so it reproduces
--       exactly.
--
--   luajit ljopt/irfuzz/fuzz.lua --enum
--       [--type num|int] [--depth D] [--ninputs N]
--       [--limit L] [--skip K] [--show I]
--       Exhaustive mode: instead of random seeds, walk
--       EVERY chain of D ops over the SLOAD inputs and
--       the fold-rule constants (enum.lua), so every
--       constant-triggered fold in that space fires at
--       least once. Traces the optimizer leaves
--       byte-identical are counted and skipped without
--       invoking z3. A finding reproduces by its
--       enumeration index: --enum ... --show I.
--
-- Needs the solver binary on PATH/LD_LIBRARY_PATH: cvc5 by
-- default (../cvc5/build/bin/cvc5), or z3 via LJOPT_SOLVER=z3.

-- The irfuzz replay works in the host VM's own jit_State. If the
-- host JIT starts recording this driver's hot loops, the replay
-- clobbers the live recording state and segfaults after ~50k
-- builds (long enum sweeps hit this; short random runs never got
-- hot enough). The driver is z3-bound anyway: run interpreted.
jit.off()

local check = require("ljopt.irfuzz.check")
local gen = require("ljopt.irfuzz.gen")
local enum = require("ljopt.irfuzz.enum")

-- Solve one formula with a standalone solver binary (not an
-- in-process library): a crash or timeout on one seed then can't
-- take down the whole run, and it matches the project's preferred
-- triage path (CLAUDE.md / use-master-z3-binary memory). Returns
-- one of "sat" / "unsat" / "unknown" / "error".
--
-- cvc5 is the default, matching the test suite. On a matched
-- 25-seed sample at the default body length it closed 20 of 25 in
-- 127s against z3's 18 in 165s. The per-seed spread is wide in
-- both directions, so LJOPT_SOLVER=z3 is still worth reaching for
-- on a seed cvc5 cannot close, and to cross-check a finding
-- against a second solver.
--
-- Read an `unknown` count on its own with care: it has no
-- denominator unless the sample is fixed, which is what made two
-- earlier comparisons here contradict each other.
local SOLVER = os.getenv("LJOPT_SOLVER") or "cvc5"
local Z3_BIN = os.getenv("LJOPT_Z3_BIN") or "../z3/build/z3"
local CVC5_BIN = os.getenv("LJOPT_CVC5_BIN") or "../cvc5/build/bin/cvc5"

local function solver_cmd(path, timeout_sec)
  if SOLVER == "z3" then
    return ("%s -T:%d %q 2>/dev/null"):format(Z3_BIN, timeout_sec, path)
  end
  -- --arrays-exp is required for the constant arrays the memory
  -- encoding builds on. The limit is milliseconds, and has to be
  -- --tlimit-per rather than --tlimit: the latter aborts the
  -- process with no verdict on its output (and dumps core), which
  -- reads here as a solver error rather than a timeout.
  return ("%s --arrays-exp --tlimit-per=%d %q 2>/dev/null")
    :format(CVC5_BIN, timeout_sec * 1000, path)
end

local function solve(formula, timeout_sec)
  local path = os.tmpname()
  local fh = assert(io.open(path, "w"))
  fh:write(formula)
  fh:close()
  local p = io.popen(solver_cmd(path, timeout_sec))
  local out = p:read("*a") or ""
  p:close()
  os.remove(path)
  -- Match a verdict line exactly rather than searching the whole
  -- output: an error message mentioning "unsatisfiable" would
  -- otherwise be read as a verdict.
  for line in out:gmatch("[^\r\n]+") do
    if line == "unsat" then return "unsat" end
    if line == "sat" then return "sat" end
    if line == "timeout" or line:match("^unknown") then return "unknown" end
  end
  return "error"
end

-- Enumerations covrun.lua already drives for coverage. Each has
-- an iter_/count_ pair and feeds check.build_from the same way
-- the hand-written sweeps do, so one table gives all of them a
-- flag, a solver sweep and a --show. `opts` reaches the iterator.
--
-- iter_bufcalls, iter_licm, iter_strops and iter_shapes are
-- absent. bufcalls leaves the BUFSTR a gap, licm wires outputs to
-- slots of the wrong type on purpose (check.lua's raw_slots), and
-- strops has two open modelling holes described in enum.lua --
-- none of those three compares what the trace computed.
--
-- shapes is the undecided one, on two counts. It is one trace per
-- fold rule over a long tail of rules, so a fault injected into
-- any single rule reaches almost none of the space: fwd_ahload,
-- the empty-TNEW load, kfold_int64comp and kfold_intarith each
-- left the sampled slices at 0 SAT, and five traces rendered
-- under the faulted build were identical to the clean ones -- the
-- fault never arrives, so nothing is validated either way. And
-- the clean sweep over the whole space reports 25 SAT and 21 LINT
-- of 2166, none triaged. Triage those and find a fault its traces
-- reach before wiring it up.
local EXTRA_SWEEPS = {
  -- Clean value oracles: every output is one ljopt models.
  abc = { desc = "array bounds checks (ABC) and the folds that drop them" },
  upval = { desc = "upvalue refs and ULOAD/USTORE forwarding" },
  -- These two reach outputs ljopt cannot model, so they run
  -- gap-tolerant: the gap is named and skipped, and what is left
  -- is still a real check. Measured 2026-08-26 -- ahref 256 of
  -- 1800 gapped (a Knil output), xref 105 of 132 (FLOAD and XLOAD
  -- of cdata fields). xref is the weak one: 45 of 132 checked.
  ahref = { desc = "AREF/HREF chains and their load forwarding",
            gaps = true },
  xref = { desc = "raw memory refs and their reassociation",
           opts = { value_outputs = true }, gaps = true },
}

local function parse_args(argv)
  local o = { seed = 1, count = 1, insns = nil, show = nil, ints = true,
              include_gaps = false, tables = false,
              enum = false, type = "num", depth = 3, ninputs = 1,
              limit = nil, skip = 0 }
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "--show" then
      o.show = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--enum" then
      o.enum = true; i = i + 1
    elseif a == "--mixed" then
      -- Mixed-type CONV enumeration (enum.iter_mixed): chains
      -- that CONV between int/i64/num, exercising the CONV fold
      -- rules.
      o.enum = true; o.mixed = true; i = i + 1
    elseif a == "--alias" then
      -- Aliasing enumeration (enum.iter_alias): store/load
      -- patterns that exercise load forwarding and DSE, i.e.
      -- LuaJIT's alias analysis rather than constant folding.
      o.enum = true; o.alias = true; i = i + 1
    elseif a == "--strings" then
      -- String enumeration (enum.iter_strings): STR_LEN folds
      -- (#const) alone and composed with int arithmetic /
      -- compares. Int-typed results keep z3 tractable.
      o.enum = true; o.strings = true; i = i + 1
    elseif a == "--xmem" then
      -- Raw FFI memory enumeration (enum.iter_xmem): XLOAD/XSTORE
      -- over the narrow C integer widths, exercising aa_xref and
      -- the narrow store-to-load forwarding CONV in lj_opt_mem.c.
      o.enum = true; o.xmem = true; i = i + 1
    elseif a == "--guard" then
      -- Guard (comparison) enumeration (enum.iter_guard): every
      -- compare op over every modeled type. Checked through the
      -- snapshot trace-exit bitvector, not a value slot.
      o.enum = true; o.guard = true; i = i + 1
    elseif a == "--narrow" then
      -- FP-narrowing enumeration (enum.iter_narrow): num ADD/SUB
      -- trees converted back to an integer, the only shape that
      -- reaches lj_opt_narrow.c from an IR replay.
      o.enum = true; o.narrow = true; i = i + 1
    elseif a == "--sink" then
      -- Allocation-sinking enumeration (enum.iter_sink): stores
      -- into a TNEW created inside the trace, the only shape that
      -- makes lj_opt_sink.c do anything.
      o.enum = true; o.sink = true; i = i + 1
    elseif a == "--buffers" then
      -- String-buffer enumeration (enum.iter_buffers): BUFHDR /
      -- BUFPUT / BUFSTR chains, the shape Lua's `..` records as
      -- and the only way into lj_opt_fold.c's buffer rules.
      o.enum = true; o.buffers = true; i = i + 1
    elseif a == "--type" then
      o.type = argv[i + 1]
      assert(o.type == "num" or o.type == "int" or o.type == "i64",
        "--type must be num, int or i64")
      o.type_given = true
      i = i + 2
    elseif a == "--depth" then
      o.depth = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--ninputs" then
      o.ninputs = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--limit" then
      o.limit = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--skip" then
      o.skip = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--seed" then
      o.seed = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--count" then
      o.count = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--insns" then
      o.insns = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--loop" then
      -- Replay as a loop trace: the optimized pass also runs
      -- lj_opt_loop, so the sweep covers unrolling and PHIs.
      o.loop = true; i = i + 1
    elseif a == "--no-ints" then
      o.ints = false; i = i + 1
    elseif a == "--include-gaps" then
      -- Also generate ops ljopt models incompletely (e.g. POW),
      -- to hunt ljopt coverage gaps rather than LuaJIT
      -- miscompiles.
      o.include_gaps = true; i = i + 1
    elseif a == "--tables" then
      -- Also generate table/array memory ops (SLOAD tab, FLOAD
      -- tab.array, AREF/HREF, ALOAD/HLOAD, ASTORE/HSTORE).
      o.tables = true; i = i + 1
    elseif EXTRA_SWEEPS[tostring(a):match("^%-%-(%a+)$") or ""] then
      o.enum = true; o.extra = a:match("^%-%-(%a+)$"); i = i + 1
    else
      error("unknown argument: " .. tostring(a))
    end
  end
  return o
end

local function gen_opts(o)
  return { insns = o.insns, ints = o.ints, exclude_gaps = not o.include_gaps,
           tables = o.tables, loop = o.loop }
end

local function show_result(r, label)
  local bar = string.rep("=", 66)
  -- A replay the recorder refused leaves no trace to render, and
  -- the skipped branch below is reached too late to catch it.
  if r.trace_unopt == nil then
    io.write(bar, "\n=== ", label, ": no trace -- the replay was refused",
      r.trace_err and (" (error %d)"):format(r.trace_err) or "", "\n",
      bar, "\n")
    return
  end
  io.write(bar, "\n=== ", label, ": UNOPT (-O0) IR trace\n", bar, "\n")
  io.write(check.render_trace(r.trace_unopt), "\n\n")
  io.write(bar, "\n=== ", label, ": OPT (-O3) IR trace\n", bar, "\n")
  io.write(check.render_trace(r.trace_opt), "\n\n")
  if #r.gaps > 0 then
    local ops = {}
    for _, gp in ipairs(r.gaps) do ops[#ops + 1] = gp.op end
    io.write("coverage gaps (outputs ljopt can't model): ",
      table.concat(ops, ", "), "\n\n")
  end
  if r.skipped then
    io.write("(no comparable outputs -- nothing to check)\n")
    return
  end
  if r.identical then
    io.write("(opt trace is byte-identical to unopt -- trivially",
      " equivalent)\n\n")
  elseif r.commut_only then
    io.write("(opt trace differs only by commutative operand",
      " swaps -- equivalent without z3)\n\n")
  end
  io.write(
    bar, "\n=== Full equivalence query (SAT => not equivalent)\n", bar, "\n"
  )
  io.write(r.formula, "\n")
end

local function show(seed, o)
  show_result(check.build(seed, gen_opts(o)), "seed " .. seed)
end

-- Enumeration options for enum.iter/enum.count from parsed args.
local function enum_type(name)
  if name == "int" then return gen.IRT_INT end
  if name == "i64" then return gen.IRT_I64 end
  return gen.IRT_NUM
end

local function enum_opts(o)
  return {
    type = enum_type(o.type),
    depth = o.depth,
    ninputs = o.ninputs,
  }
end

-- Reproduce one enumerated trace by its 1-based index (stable:
-- enumeration order is deterministic for fixed
-- type/depth/ninputs).
local function show_enum(idx, o)
  local i = 0
  for tr in enum.iter(enum_opts(o)) do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("enum #%d (type=%s depth=%d ninputs=%d)")
          :format(idx, o.type, o.depth, o.ninputs))
      return
    end
  end
  error(("enum index %d out of range (space has %d traces)")
    :format(idx, i))
end

-- Shared per-trace bookkeeping for run()/run_enum(). `c` is the
-- mutable counter table; `label` names the trace in findings
-- ("seed=7" / "#123"); `hint` is the reproduce command for a SAT.
local function check_one(r, c, timeout_sec, label, hint, strict)
  -- Malformed-IR findings (see check.lint_conv_types): reported
  -- independently of the equivalence verdict, because the class
  -- it catches (type field disagreeing with the CONV mode) is
  -- invisible to the SMT check by construction.
  if r.lint and #r.lint > 0 then
    c.lint = c.lint + 1
    io.write(("LINT  %s  CONV type/mode mismatch: %s -- reproduce: %s\n")
      :format(label, table.concat(r.lint, "; "), hint))
  end
  if #r.gaps > 0 then
    c.gap = c.gap + 1
    local ops = {}
    for _, gp in ipairs(r.gaps) do
      c.gap_ops[gp.op] = (c.gap_ops[gp.op] or 0) + 1
      ops[#ops + 1] = gp.op
    end
    -- In strict mode (the default -- everything the generator
    -- emits is supposed to be modeled, since the known-gap ops
    -- POW/BROL/BROR are already excluded) a gap means ljopt
    -- cannot model an op we thought it could: a real finding.
    -- Fail loudly rather than silently dropping the output.
    if strict then
      error(("UNMODELED OP %s: ljopt cannot model output op(s): %s"
        .. " -- reproduce: %s"):format(label, table.concat(ops, ", "), hint))
    end
    io.write(("GAP   %s  ljopt can't model output op(s): %s\n")
      :format(label, table.concat(ops, ", ")))
  end
  if r.skipped then
    c.skip = c.skip + 1
    return
  end
  if r.identical then
    -- Optimizer left the trace byte-identical: trivially
    -- equivalent, no z3 needed.
    c.ident = c.ident + 1
    return
  end
  if r.commut_only then
    -- Only provably-commutative operand swaps: equivalent by
    -- commutativity, and z3 burns ~30s per FP query re-proving
    -- it, so skip.
    c.commut = c.commut + 1
    return
  end
  local res = solve(r.formula, timeout_sec)
  if res == "sat" then
    c.sat = c.sat + 1
    io.write((
      "SAT   %s  LuaJIT-BUG CANDIDATE (all outputs "
      .. "modeled) -- inspect: %s\n"
    ):format(label, hint))
  elseif res == "unsat" then
    c.unsat = c.unsat + 1
  else
    c.unknown = c.unknown + 1
    io.write(("UNKNOWN %s (%s %s)\n"):format(label, SOLVER, res))
  end
end

local function counters()
  return { sat = 0, unsat = 0, unknown = 0, skip = 0, gap = 0,
           ident = 0, commut = 0, lint = 0, gap_ops = {} }
end

local function report(c, total)
  io.write((
    "\ndone: %d unsat, %d SAT(bug candidates), %d unknown, "
    .. "%d trivially-identical, %d commut-swap-only, "
    .. "%d gap-seeds, %d skipped, %d LINT (of %d)\n"
  ):format(c.unsat, c.sat, c.unknown, c.ident, c.commut,
    c.gap, c.skip, c.lint, total))
  if next(c.gap_ops) then
    io.write("ljopt coverage gaps by op: ")
    local parts = {}
    for op, n in pairs(c.gap_ops) do
      parts[#parts + 1] = ("%s x%d"):format(op, n)
    end
    io.write(table.concat(parts, ", "), "\n")
  end
end

local function run(o)
  local timeout_sec = tonumber(os.getenv("LJOPT_Z3_TIMEOUT")) or 15
  local c = counters()
  local strict = not o.include_gaps
  for seed = o.seed, o.seed + o.count - 1 do
    local r = check.build(seed, gen_opts(o))
    check_one(r, c, timeout_sec, "seed=" .. seed, "--show " .. seed, strict)
  end
  report(c, o.count)
  return c.sat
end

-- Exhaustive sweep over enum.lua's chain space. Reports findings
-- by enumeration index; reproduce with the printed --show command
-- (same --type/--depth/--ninputs).
-- Shared sweep body for both single-type (iter/count) and
-- mixed-type (iter_mixed/count_mixed) enumeration. `make_iter`
-- returns a fresh trace iterator; `total` is the space size;
-- `repro` is the reproduce command prefix (index appended).
local function sweep(o, make_iter, total, repro, gaps_ok)
  local timeout_sec = tonumber(os.getenv("LJOPT_Z3_TIMEOUT")) or 15
  if o.skip > 0 then io.write((", skipping first %d"):format(o.skip)) end
  if o.limit then io.write((", checking at most %d"):format(o.limit)) end
  io.write("\n")
  local strict = not (o.include_gaps or gaps_ok)
  local c = counters()
  local idx, checked = 0, 0
  for tr in make_iter() do
    idx = idx + 1
    if idx > o.skip then
      checked = checked + 1
      local r = check.build_from(tr.insns, tr.outputs, { loop = o.loop })
      check_one(r, c, timeout_sec, "#" .. idx, repro .. " " .. idx, strict)
      if checked % 2000 == 0 then
        io.write(("... %d/%d checked (%d z3 calls, %d sat)\n")
          :format(checked, o.limit or total - o.skip,
            c.unsat + c.sat + c.unknown, c.sat))
      end
      if o.limit and checked >= o.limit then break end
    end
  end
  report(c, checked)
  return c.sat
end

local function run_enum(o)
  local eo = enum_opts(o)
  local total = enum.count(eo)
  io.write(("enum sweep: type=%s depth=%d ninputs=%d -- %d traces in space")
    :format(o.type, o.depth, o.ninputs, total))
  local repro = ("--enum --type %s --depth %d --ninputs %d --show")
    :format(o.type, o.depth, o.ninputs)
  return sweep(o, function() return enum.iter(eo) end, total, repro)
end

local function run_mixed(o)
  local total = enum.count_mixed({ depth = o.depth })
  io.write(("mixed CONV sweep: depth=%d -- %d traces in space")
    :format(o.depth, total))
  local repro = ("--mixed --depth %d --show"):format(o.depth)
  return sweep(o, function() return enum.iter_mixed({ depth = o.depth }) end,
    total, repro)
end

local function run_strings(o)
  local total = enum.count_strings()
  io.write(("string sweep: STR_LEN folds + int compose -- %d traces")
    :format(total))
  return sweep(o, function() return enum.iter_strings() end, total,
    "--strings --show")
end

local function show_strings(idx, o)
  local i = 0
  for tr in enum.iter_strings() do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("string #%d"):format(idx))
      return
    end
  end
  error(("string index %d out of range (space has %d traces)")
    :format(idx, i))
end

local function run_xmem(o)
  local total = enum.count_xmem()
  io.write(("xmem sweep: FFI load/store forwarding -- %d traces")
    :format(total))
  return sweep(o, function() return enum.iter_xmem() end, total,
    "--xmem --show")
end

local function show_xmem(idx, o)
  local i = 0
  for tr in enum.iter_xmem() do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("xmem #%d"):format(idx))
      return
    end
  end
  error(("xmem index %d out of range (space has %d traces)")
    :format(idx, i))
end

local function run_alias(o)
  local total = enum.count_alias()
  io.write(("alias sweep: store/load forwarding + DSE -- %d traces")
    :format(total))
  return sweep(o, function() return enum.iter_alias() end, total,
    "--alias --show")
end

local function show_alias(idx, o)
  local i = 0
  for tr in enum.iter_alias() do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("alias #%d"):format(idx))
      return
    end
  end
  error(("alias index %d out of range (space has %d traces)")
    :format(idx, i))
end

-- Guard options: restrict to one type when --type is given, else
-- sweep int/num/i64.
local function guard_opts(o)
  local go = { depth = o.depth }
  if o.type_given then
    go.types = { ({ int = 19, num = 14, i64 = 21 })[o.type] }
  end
  return go
end

local function run_guard(o)
  local go = guard_opts(o)
  local total = enum.count_guard(go)
  io.write(("guard sweep: type=%s depth=%d -- %d traces in space")
    :format(o.type_given and o.type or "int,num,i64", o.depth, total))
  local repro = ("--guard --depth %d%s --show"):format(o.depth,
    o.type_given and (" --type " .. o.type) or "")
  return sweep(o, function() return enum.iter_guard(go) end, total, repro)
end

local function show_guard(idx, o)
  local i = 0
  for tr in enum.iter_guard(guard_opts(o)) do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("guard #%d (depth=%d)"):format(idx, o.depth))
      return
    end
  end
  error(("guard index %d out of range (space has %d traces)")
    :format(idx, i))
end

local function run_narrow(o)
  local total = enum.count_narrow()
  io.write(("narrow sweep: %d traces in space"):format(total))
  return sweep(o, function() return enum.iter_narrow() end, total,
    "--narrow --show")
end

local function show_narrow(idx, o)
  local i = 0
  for tr in enum.iter_narrow() do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("narrow #%d"):format(idx))
      return
    end
  end
  error(("narrow index %d out of range (space has %d traces)")
    :format(idx, i))
end

local function run_sink(o)
  local total = enum.count_sink()
  io.write(("sink sweep: %d traces in space"):format(total))
  return sweep(o, function() return enum.iter_sink() end, total,
    "--sink --show")
end

local function show_sink(idx, o)
  local i = 0
  for tr in enum.iter_sink() do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("sink #%d"):format(idx))
      return
    end
  end
  error(("sink index %d out of range (space has %d traces)")
    :format(idx, i))
end

local function run_buffers(o)
  local total = enum.count_buffers()
  io.write(("buffer sweep: %d traces in space"):format(total))
  return sweep(o, function() return enum.iter_buffers() end, total,
    "--buffers --show")
end

local function show_buffers(idx, o)
  local i = 0
  for tr in enum.iter_buffers() do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("buffers #%d"):format(idx))
      return
    end
  end
  error(("buffers index %d out of range (space has %d traces)")
    :format(idx, i))
end

-- Reproduce one mixed-enumeration trace by its 1-based index.
local function show_mixed(idx, o)
  local i = 0
  for tr in enum.iter_mixed({ depth = o.depth }) do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("mixed #%d (depth=%d)"):format(idx, o.depth))
      return
    end
  end
  error(("mixed index %d out of range (space has %d traces)")
    :format(idx, i))
end

-- Sweep and reproduce for every EXTRA_SWEEPS entry.
local function run_extra(o)
  local name = o.extra
  local e = EXTRA_SWEEPS[name]
  local total = enum["count_" .. name](e.opts)
  io.write(("%s sweep: %s -- %d traces"):format(name, e.desc, total))
  return sweep(o, function() return enum["iter_" .. name](e.opts) end,
    total, ("--%s --show"):format(name), e.gaps)
end

local function show_extra(idx, o)
  local name = o.extra
  local i = 0
  for tr in enum["iter_" .. name](EXTRA_SWEEPS[name].opts) do
    i = i + 1
    if i == idx then
      show_result(check.build_from(tr.insns, tr.outputs, {}),
        ("%s #%d"):format(name, idx))
      return
    end
  end
  error(("%s index %d out of range (space has %d traces)")
    :format(name, idx, i))
end

local o = parse_args(arg)
if o.show ~= nil then
  if o.extra then show_extra(o.show, o)
  elseif o.strings then show_strings(o.show, o)
  elseif o.xmem then show_xmem(o.show, o)
  elseif o.alias then show_alias(o.show, o)
  elseif o.guard then show_guard(o.show, o)
  elseif o.narrow then show_narrow(o.show, o)
  elseif o.sink then show_sink(o.show, o)
  elseif o.buffers then show_buffers(o.show, o)
  elseif o.mixed then show_mixed(o.show, o)
  elseif o.enum then show_enum(o.show, o)
  else show(o.show, o) end
  os.exit(0)
end
local n_sat = (o.extra and run_extra(o))
  or (o.strings and run_strings(o))
  or (o.xmem and run_xmem(o))
  or (o.alias and run_alias(o))
  or (o.guard and run_guard(o))
  or (o.narrow and run_narrow(o))
  or (o.sink and run_sink(o))
  or (o.buffers and run_buffers(o))
  or (o.mixed and run_mixed(o))
  or (o.enum and run_enum(o)) or run(o)
os.exit(n_sat == 0 and 0 or 1)
