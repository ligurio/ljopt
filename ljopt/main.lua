local jit = require("jit")
local utils = require("ljopt.utils")
local ljopt = require("ljopt")
local runtime = require("ljopt.runtime")
local ljopt_config = require("ljopt.config")
local smt_constants = require("ljopt.smt_constants")

local exit_codes = {
  OK = 0,
  ERR_BAD_LUA_RUNTIME = 1,
  ERR_BAD_LUA_CHUNK = 2,
  ERR_VERIFICATION_FAILED = 3,
  ERR_SMT_UNKNOWN = 4,
}

-- Wall-clock source for per-trace and total verification times.
-- Uses CLOCK_MONOTONIC through FFI when available, falls back to
-- CPU time (os.clock) otherwise.
local monotonic_now
do
  local ok_ffi, ffi = pcall(require, "ffi")
  local ok_cdef = false
  if ok_ffi then
    ok_cdef = pcall(ffi.cdef, [[
typedef struct { long tv_sec; long tv_nsec; } ljopt_timespec;
int clock_gettime(int clk_id, ljopt_timespec *tp);
]])
  end
  if ok_ffi and ok_cdef then
    local ts = ffi.new("ljopt_timespec")
    monotonic_now = function()
      if ffi.C.clock_gettime(1, ts) == 0 then
        return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
      end
      return os.clock()
    end
  else
    monotonic_now = os.clock
  end
end

local USAGE_MESSAGE = [[
Usage: ljopt [options] [script]

A Lua chunk can be passed as a file, as a string argument or
through stdin. By default ljopt translates the chunk and prints
the SMT-LIB formula to stdout.

A Lua chunk can be passed as a file, as a string argument or
through stdin.

Options:
   -c, --check                 Verify the traces with an SMT solver
                               (Z3 or cvc5) and print the result.
   -                           Read a Lua chunk from stdin.
]]

-- Returns a solver instance or nil when no usable solver is
-- found. The backend selected by LJOPT_SMT (cvc5 by default)
-- is tried first, then the other one, so any available solver
-- (Z3 or cvc5) is used. A backend whose library is missing or
-- too old fails its probe and is skipped.
local function solver_backends()
  local preferred = ljopt_config.get_smt_solver()
  if preferred == "cvc5" then
    return {"cvc5", "z3"}
  elseif preferred == "z3" then
    return {"z3", "cvc5"}
  end
  return {"cvc5", "z3"}
end

local function find_solver()
  for _, backend in ipairs(solver_backends()) do
    local has_backend, smt = pcall(require, "ljopt.smtlib2_" .. backend)
    if has_backend then
      local is_ok, solver = pcall(smt.new)
      if is_ok then
        return solver
      end
    end
  end
end

if jit == nil then
  utils.fatal_msg("Unsupported Lua runtime.", exit_codes.ERR_BAD_LUA_RUNTIME)
end

local check_requested = false
local script
for i = 1, #arg do
  local opt = arg[i]
  if opt == "-c" or opt == "--check" then
    check_requested = true
  elseif opt == "-" or opt:sub(1, 1) ~= "-" then
    if script ~= nil then
      io.stderr:write(USAGE_MESSAGE)
      os.exit(exit_codes.OK)
    end
    script = opt
  else
    io.stderr:write(USAGE_MESSAGE)
    os.exit(exit_codes.OK)
  end
end

if script == nil then
  io.stderr:write(USAGE_MESSAGE)
  os.exit(exit_codes.OK)
end

-- The Lua chunk can be passed in a file or directly as a string.
-- A dash means the chunk should be read from stdin.
-- The chunkname lets trace start locations be reported as
-- "<name>:<line>" instead of an anonymous address.
local lua_code
local chunkname
if script == "-" then
  lua_code = io.stdin:read("*a")
  chunkname = "@<stdin>"
else
  local is_exist, fh = utils.file_exists(script)
  if is_exist then
    lua_code = fh:read("*a")
    fh:close()
    chunkname = "@" .. script
  else
    lua_code = script
    chunkname = "@<string>"
  end
end

if not lua_code or
   #lua_code == 0 then
  io.stderr:write(USAGE_MESSAGE)
  utils.fatal_msg("Lua chunk is empty.", exit_codes.ERR_BAD_LUA_CHUNK)
end

local chunk, chunk_err = load(lua_code, chunkname)
if chunk == nil then
  utils.fatal_msg("Syntax error in Lua chunk: " .. chunk_err,
    exit_codes.ERR_BAD_LUA_CHUNK)
end

local env = setmetatable({}, {__index = _G})
local mt = getmetatable("string")
setfenv(chunk, env)
local ok, err = runtime.capture(chunk)
debug.setmetatable("", mt)
if not ok then
  utils.fatal_msg("Runtime error: " .. err, exit_codes.ERR_BAD_LUA_CHUNK)
end
-- Check for runtime errors above may trigger trace recording,
-- flush traces before proceeding.
jit.flush()

-- By default print the SMT-LIB formula to stdout.
if not check_requested then
  io.stdout:write(ljopt.ir.translate_to_smt(lua_code, chunkname))
  os.exit(exit_codes.OK)
end

local solver = find_solver()
if solver == nil then
  io.stderr:write("SMT solver is not available (install Z3 or cvc5), "
    .. "the SMT-LIB formula is printed to stdout.\n")
  io.stdout:write(ljopt.ir.translate_to_smt(lua_code, chunkname))
  os.exit(exit_codes.ERR_SMT_UNKNOWN)
end

-- translate_to_smt() ends every trace with (reset), so feeding
-- the whole buffer to a solver checks an empty context and
-- always answers SAT. Check each trace formula on its own, the
-- way the test suite does.
-- Flush the solver banner out before verdicts start streaming,
-- otherwise it would only surface with the first flush below.
io.stdout:flush()
local start_time = monotonic_now()
local traces, trace_locs = ljopt.ir.traces_to_smt(lua_code, chunkname)

-- Traces are checked one by one and their verdict is printed as
-- soon as a formula is ready. To make the stream deterministic
-- the traces are first sorted by their start location.
local function loc_key(loc)
  local file, line = loc:match("^(.*):(%d+)$")
  if file ~= nil then
    return file, tonumber(line)
  end
  return loc, 0
end
local function loc_less(loc_a, loc_b)
  local file_a, line_a = loc_key(loc_a)
  local file_b, line_b = loc_key(loc_b)
  if file_a ~= file_b then
    return file_a < file_b
  elseif line_a ~= line_b then
    return line_a < line_b
  end
  return loc_a < loc_b
end
local order = {}
for traceno in pairs(traces) do
  table.insert(order, traceno)
end
table.sort(order, function(a, b)
  return loc_less(
    trace_locs[a] or tostring(a), trace_locs[b] or tostring(b)
  )
end)
if #order == 0 then
  io.stderr:write("No traces recorded, nothing to verify.\n")
  os.exit(exit_codes.OK)
end

local n_passed = 0
local n_failed = 0
local n_timed_out = 0
local n_traces = #order
local failed_list = {}
local timeout_list = {}
-- Dots of every result line reach this column, so the verdict and
-- time columns line up across traces with different locations.
local RESULT_COLUMN = 62
-- Trace numbers are right-aligned in a fixed-width field so the
-- colon after a number (and the location that follows it) stays
-- in the same column whether the number has one digit or two.
local function rjust(n, width)
  local s = tostring(n)
  return string.rep(" ", width - #s) .. s
end
local nw = #("%d"):format(n_traces)
local counter_w = 2 * nw + 2
local tag_w = nw + 1
for idx, traceno in ipairs(order) do
  local loc = trace_locs[traceno] or tostring(traceno)
  local start_tag = rjust(idx, tag_w)
  io.stdout:write(string.rep(" ", counter_w) ..
    ("Start %s:  %s\n"):format(start_tag, loc))
  io.stdout:flush()
  local smt_formula = smt_constants.LJOPT_SMTLIB .. traces[traceno]
  assert(solver:parse(smt_formula) == true)
  local solve_start = monotonic_now()
  local check_res = solver:check(smt_formula)
  local solve_time = monotonic_now() - solve_start
  local verdict
  if check_res == solver.result.SAT then
    verdict = "Failed"
    n_failed = n_failed + 1
    table.insert(failed_list, {idx = idx, loc = loc})
  elseif check_res == solver.result.UNKNOWN then
    verdict = "Timeout"
    n_timed_out = n_timed_out + 1
    table.insert(timeout_list, {idx = idx, loc = loc})
  else
    verdict = "Passed"
    n_passed = n_passed + 1
  end
  local prefix = rjust(idx, nw) .. "/" .. n_traces .. " "
    .. "Trace " .. rjust("#" .. idx, tag_w) .. ":  " .. loc
  local dots = RESULT_COLUMN - #prefix
  if dots < 1 then dots = 1 end
  io.stdout:write(prefix .. string.rep(".", dots) ..
    ("   %-10s%.2f sec\n"):format(verdict, solve_time))
  io.stdout:flush()
end

io.stdout:write("\n")
local passed_pct = math.floor(100 * n_passed / n_traces)
if n_timed_out > 0 then
  io.stdout:write(("%d%% traces passed, %d traces failed, "
    .. "%d traces timed out out of %d\n")
    :format(passed_pct, n_failed, n_timed_out, n_traces))
else
  io.stdout:write(("%d%% traces passed, %d traces failed out of %d\n")
    :format(passed_pct, n_failed, n_traces))
end
io.stdout:write("\n")
io.stdout:write(("Total verification time (real) = %6.2f sec\n")
  :format(monotonic_now() - start_time))

if #failed_list > 0 then
  io.stdout:write("\nThe following traces FAILED:\n")
  for _, f in ipairs(failed_list) do
    io.stdout:write(("%10d - %s (Failed)\n"):format(f.idx, f.loc))
  end
end
if #timeout_list > 0 then
  io.stdout:write("\nThe following traces TIMED OUT:\n")
  for _, t in ipairs(timeout_list) do
    io.stdout:write(("%10d - %s (Timeout)\n"):format(t.idx, t.loc))
  end
end

local rc = exit_codes.OK
if n_failed > 0 then
  rc = exit_codes.ERR_VERIFICATION_FAILED
elseif n_timed_out > 0 then
  rc = exit_codes.ERR_SMT_UNKNOWN
end
os.exit(rc)
