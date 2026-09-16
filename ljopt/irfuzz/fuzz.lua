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
-- Needs z3 on LD_LIBRARY_PATH (see CLAUDE.md: ../z3/build).

local check = require("ljopt.irfuzz.check")

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
              include_gaps = false, tables = false }
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "--show" then
      o.show = tonumber(argv[i + 1]); i = i + 2
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

local function show(seed, o)
  local r = check.build(seed, gen_opts(o))
  local bar = string.rep("=", 66)
  io.write(bar, "\n=== seed ", seed, ": UNOPT (-O0) IR trace\n", bar, "\n")
  io.write(check.render_trace(r.trace_unopt), "\n\n")
  io.write(bar, "\n=== seed ", seed, ": OPT (-O3) IR trace\n", bar, "\n")
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
  io.write(
    bar, "\n=== Full equivalence query (SAT => not equivalent)\n", bar, "\n"
  )
  io.write(r.formula, "\n")
end

local function run(o)
  local timeout_sec = tonumber(os.getenv("LJOPT_Z3_TIMEOUT")) or 15
  local n_sat, n_unsat, n_unknown, n_skip, n_gap = 0, 0, 0, 0, 0
  local gap_ops = {}
  for seed = o.seed, o.seed + o.count - 1 do
    local r = check.build(seed, gen_opts(o))
    if #r.gaps > 0 then
      n_gap = n_gap + 1
      local ops = {}
      for _, gp in ipairs(r.gaps) do
        gap_ops[gp.op] = (gap_ops[gp.op] or 0) + 1
        ops[#ops + 1] = gp.op
      end
      io.write(("GAP   seed=%d  ljopt can't model output op(s): %s\n")
        :format(seed, table.concat(ops, ", ")))
    end
    if r.skipped then
      n_skip = n_skip + 1
      goto continue
    end
    local res = z3_solve(r.formula, timeout_sec)
    if res == "sat" then
      n_sat = n_sat + 1
      io.write((
        "SAT   seed=%d  LuaJIT-BUG CANDIDATE (all outputs "
        .. "modeled) -- inspect: --show %d\n"
      ):format(seed, seed))
    elseif res == "unsat" then
      n_unsat = n_unsat + 1
    else
      n_unknown = n_unknown + 1
      io.write(("UNKNOWN seed=%d (z3 %s)\n"):format(seed, res))
    end
    ::continue::
  end
  io.write((
    "\ndone: %d unsat, %d SAT(bug candidates), %d unknown, "
    .. "%d gap-seeds, %d skipped (of %d)\n"
  ):format(n_unsat, n_sat, n_unknown, n_gap, n_skip, o.count))
  if next(gap_ops) then
    io.write("ljopt coverage gaps by op: ")
    local parts = {}
    for op, c in pairs(gap_ops) do
      parts[#parts + 1] = ("%s x%d"):format(op, c)
    end
    io.write(table.concat(parts, ", "), "\n")
  end
  return n_sat
end

local o = parse_args(arg)
if o.show ~= nil then
  show(o.show, o)
  os.exit(0)
end
local n_sat = run(o)
os.exit(n_sat == 0 and 0 or 1)
