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
-- Needs z3 on LD_LIBRARY_PATH (see CLAUDE.md: ../z3/build).

local check = require("ljopt.irfuzz.check")
local gen = require("ljopt.irfuzz.gen")
local enum = require("ljopt.irfuzz.enum")

-- Solve one formula with the standalone z3 binary (not in-process
-- libz3): a crash or timeout on one seed then can't take down the
-- whole run, and it matches the project's preferred triage path
-- (CLAUDE.md / use-master-z3-binary memory). Returns one of
-- "sat" / "unsat" / "unknown" / "error".
local Z3_BIN = os.getenv("LJOPT_Z3_BIN") or "../z3/build/z3"
local function z3_solve(formula, timeout_sec)
  local path = os.tmpname()
  local fh = assert(io.open(path, "w"))
  fh:write(formula)
  fh:close()
  local cmd = ("%s -T:%d %q 2>/dev/null"):format(Z3_BIN, timeout_sec, path)
  local p = io.popen(cmd)
  local out = p:read("*a") or ""
  p:close()
  os.remove(path)
  if out:find("unsat", 1, true) then return "unsat" end
  if out:find("sat", 1, true) then return "sat" end
  if out:find("timeout", 1, true) or out:find("unknown", 1, true) then
    return "unknown"
  end
  return "error"
end

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
    elseif a == "--type" then
      o.type = argv[i + 1]
      assert(o.type == "num" or o.type == "int",
        "--type must be num or int")
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
    else
      error("unknown argument: " .. tostring(a))
    end
  end
  return o
end

local function gen_opts(o)
  return { insns = o.insns, ints = o.ints, exclude_gaps = not o.include_gaps,
           tables = o.tables }
end

local function show_result(r, label)
  local bar = string.rep("=", 66)
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
local function enum_opts(o)
  return {
    type = (o.type == "int") and gen.IRT_INT or gen.IRT_NUM,
    depth = o.depth,
    ninputs = o.ninputs,
  }
end

-- Reproduce one enumerated trace by its 1-based index (stable:
-- enumeration order is deterministic for fixed type/depth/ninputs).
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
local function check_one(r, c, timeout_sec, label, hint)
  if #r.gaps > 0 then
    c.gap = c.gap + 1
    local ops = {}
    for _, gp in ipairs(r.gaps) do
      c.gap_ops[gp.op] = (c.gap_ops[gp.op] or 0) + 1
      ops[#ops + 1] = gp.op
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
  local res = z3_solve(r.formula, timeout_sec)
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
    io.write(("UNKNOWN %s (z3 %s)\n"):format(label, res))
  end
end

local function counters()
  return { sat = 0, unsat = 0, unknown = 0, skip = 0, gap = 0,
           ident = 0, commut = 0, gap_ops = {} }
end

local function report(c, total)
  io.write((
    "\ndone: %d unsat, %d SAT(bug candidates), %d unknown, "
    .. "%d trivially-identical, %d commut-swap-only, "
    .. "%d gap-seeds, %d skipped (of %d)\n"
  ):format(c.unsat, c.sat, c.unknown, c.ident, c.commut,
    c.gap, c.skip, total))
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
  for seed = o.seed, o.seed + o.count - 1 do
    local r = check.build(seed, gen_opts(o))
    check_one(r, c, timeout_sec, "seed=" .. seed, "--show " .. seed)
  end
  report(c, o.count)
  return c.sat
end

-- Exhaustive sweep over enum.lua's chain space. Reports findings
-- by enumeration index; reproduce with the printed --show command
-- (same --type/--depth/--ninputs).
local function run_enum(o)
  local timeout_sec = tonumber(os.getenv("LJOPT_Z3_TIMEOUT")) or 15
  local eo = enum_opts(o)
  local total = enum.count(eo)
  io.write(("enum sweep: type=%s depth=%d ninputs=%d -- %d traces in space")
    :format(o.type, o.depth, o.ninputs, total))
  if o.skip > 0 then io.write((", skipping first %d"):format(o.skip)) end
  if o.limit then io.write((", checking at most %d"):format(o.limit)) end
  io.write("\n")

  local repro = ("--enum --type %s --depth %d --ninputs %d --show")
    :format(o.type, o.depth, o.ninputs)
  local c = counters()
  local idx, checked = 0, 0
  for tr in enum.iter(eo) do
    idx = idx + 1
    if idx > o.skip then
      checked = checked + 1
      local r = check.build_from(tr.insns, tr.outputs, {})
      check_one(r, c, timeout_sec, "#" .. idx, repro .. " " .. idx)
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

local o = parse_args(arg)
if o.show ~= nil then
  if o.enum then show_enum(o.show, o) else show(o.show, o) end
  os.exit(0)
end
local n_sat = o.enum and run_enum(o) or run(o)
os.exit(n_sat == 0 and 0 or 1)
