local jit = require("jit")
local utils = require("ljopt.utils")
local ljopt = require("ljopt")
local runtime = require("ljopt.runtime")

local exit_codes = {
  OK = 0,
  ERR_BAD_LUA_RUNTIME = 1,
  ERR_BAD_LUA_CHUNK = 2,
  ERR_VERIFICATION_FAILED = 3,
  ERR_SMT_UNKNOWN = 4,
}

local USAGE_MESSAGE = [[
Usage: ljopt [options] script [trace_number]

A Lua chunk can be passed as a file, as a string argument or
through stdin. By default ljopt translates the chunk and prints
the SMT-LIB formula to stdout.

Options:
   -c, --check                 Verify the traces with an SMT solver
                               (Z3 or cvc5) and print the result.
   -                           Read a Lua chunk from stdin.

The optional trace_number (a positive integer, as shown in the
--check output by "N/M Trace #N") restricts the action to a single
trace: without --check only the SMT-LIB formula for that trace is
printed, with --check only that trace is verified.
]]

local function trace_number_error(num, total)
  io.stderr:write(("ljopt: trace number %d is out of range (1..%d)\n")
    :format(num, total))
  os.exit(1)
end

if jit == nil then
  utils.fatal_msg("Unsupported Lua runtime.", exit_codes.ERR_BAD_LUA_RUNTIME)
end

local check_requested = false
local trace_number
local script
local n_positional = 0
for i = 1, #arg do
  local opt = arg[i]
  if opt == "-c" or opt == "--check" then
    check_requested = true
  elseif opt == "-" or opt:sub(1, 1) ~= "-" then
    n_positional = n_positional + 1
    if n_positional == 1 then
      script = opt
    elseif n_positional == 2 then
      if not opt:match("^[1-9]%d*$") then
        io.stderr:write(USAGE_MESSAGE)
        os.exit(exit_codes.OK)
      end
      trace_number = tonumber(opt)
    else
      io.stderr:write(USAGE_MESSAGE)
      os.exit(exit_codes.OK)
    end
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

-- By default print the SMT-LIB formula to stdout. With a trace
-- number only that trace is printed.
if not check_requested then
  if trace_number == nil then
    io.stdout:write(ljopt.ir.translate_to_smt(lua_code, chunkname))
    os.exit(exit_codes.OK)
  end
  local traces, trace_locs = ljopt.ir.traces_to_smt(lua_code, chunkname)
  local order = utils.build_order(traces, trace_locs)
  if trace_number > #order then
    trace_number_error(trace_number, #order)
  end
  io.stdout:write(ljopt.ir.wrap_trace(traces[order[trace_number]]))
  os.exit(exit_codes.OK)
end

local solver = utils.find_solver()
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
local start_time = utils.clock_monotonic()
local traces, trace_locs = ljopt.ir.traces_to_smt(lua_code, chunkname)

-- Traces are checked one by one and their verdict is printed as
-- soon as a formula is ready. To make the stream deterministic
-- the traces are first sorted by their start location.
local order = utils.build_order(traces, trace_locs)
local n_traces = #order
if n_traces == 0 and trace_number == nil then
  io.stderr:write("No traces recorded, nothing to verify.\n")
  os.exit(exit_codes.OK)
end
if trace_number ~= nil and trace_number > n_traces then
  trace_number_error(trace_number, n_traces)
end
-- When a trace number is given, only that trace is verified. It
-- keeps its original number in the N/M report below.
local selected = utils.select_traces(order, trace_number)
os.exit(utils.verify_traces(solver, traces, trace_locs, selected,
  n_traces, start_time, exit_codes))
