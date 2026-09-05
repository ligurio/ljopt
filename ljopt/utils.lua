local bit = require("bit")
local ffi = require("ffi")
local ljopt_config = require("ljopt.config")
local op_type = require('ljopt.ir.op_type')

local string_gsub = string.gsub

ffi.cdef([[
typedef struct { long tv_sec; long tv_nsec; } ljopt_timespec;
int clock_gettime(int clk_id, ljopt_timespec *tp);
]])

local function debug_msg(s)
    if ljopt_config.is_debug_mode() then
        io.stderr:write(s .. "\n")
    end
end

local function fatal_msg(s, exit_code)
    io.stderr:write(s .. "\n")
    os.exit(exit_code)
end

-- Simplest hash for strings:
-- https://ru.wikipedia.org/wiki/FNV
local function fnv1a_hash(str)
    local hash = 2166136261
    for i = 1, #str do
        hash = bit.bxor(hash, string.byte(str, i))
        hash = (hash * 16777619) % 2^32
    end
    return hash
end

local function join_strings(string_array)
    return table.concat(string_array, "\n")
end

local function unreachable(s)
    error(s, 2)
end

local function merge_tables(t1, t2)
    local merged = {}
    local all_keys = {}
    for k, _v in pairs(t1) do
        if ljopt_config.is_strict_mode() then
            assert(t2[k] ~= nil, "key does not exist " .. k)
            all_keys[k] = true
        elseif t2[k] ~= nil then
            all_keys[k] = true
        end
    end
    if ljopt_config.is_strict_mode() then
        for k, _v in pairs(t2) do
            assert(t1[k] ~= nil, "key does not exist " .. k)
        end
    end

    for k, _v in pairs(all_keys) do
        assert(t1[k] ~= nil, "t1 is nil")
        assert(t2[k] ~= nil, "t2 is nil")
        merged[k] = {t1[k], t2[k]}
    end

    return merged
end

-- Takes as input snapshots and exits.
-- Snapshot table is uid -> Snapshot.
-- We need to add to every snapshot number of instructions with
-- guard. The function sorts snapshots by nins, and walks over
-- a trace adding guard to the last snapshot.
local function enrich_snapshots_with_exits(nodes, trace_record)
    local ins2snap = {}
    for uid, ins_snap in pairs(trace_record.snapshots) do
        trace_record.snapshots[uid].exits = {}
        for _, ex in pairs(ins_snap.nins) do
            table.insert(ins2snap, {nins = ex, uid = uid})
        end
    end
    table.sort(ins2snap, function(a, b)
        return a.nins < b.nins
    end)
    for _, snap in pairs(ins2snap) do
        debug_msg(("Snapshot %d %d\n"):format(
                snap.nins, snap.uid
        ))
    end

    local cur_snap_id = 1
    local used_snapshots = {}
    for ir_id, ir_node in pairs(nodes) do
        if (ir_node ~= nil and ir_node:get_flags().irt_guard) then
            -- Search for associated snapshot.
            local is_inc = false
            while (#ins2snap >= cur_snap_id + 1 and
                   ins2snap[cur_snap_id + 1].nins <= ir_id) do
                cur_snap_id = cur_snap_id + 1
                is_inc = true
            end
            if is_inc then
                if used_snapshots[ins2snap[cur_snap_id].uid] then
                    return false
                end
                used_snapshots[ins2snap[cur_snap_id].uid] = true
            end
            if (ins2snap[cur_snap_id].nins <= ir_id) then
                local snap_uid = ins2snap[cur_snap_id].uid
                table.insert(trace_record.snapshots[snap_uid].exits, ir_id)
                debug_msg(("Snapshot %d %d depends on %d"):format(
                    ins2snap[cur_snap_id].nins, snap_uid, ir_id
                ))
            end
        end
    end
    return true
end

-- Resolve constant num value from an operand.
-- Returns these if known, nil otherwise.
local function resolve_const(op, ctx, expected_type)
    if expected_type ~= nil then
        assert(op.type == expected_type or op.type == op_type.SSA,
            ("expected %s, got %s"):format(expected_type, op.type)
        )
    end
    if op:is_str() then
        return op:get_str()
    elseif op:is_num() then
        return op:get_num()
    elseif op:is_ssa() then
        return ctx.const_nums[op:get_ssa()]
    end
    return nil
end

-- Like `resolve_const`, but for string operands. Falls back to
-- `ctx.const_strs` for SSA refs (e.g. TOSTR/HLOAD that have
-- stamped a known string value). Without this,
-- str HSTORE -> HLOAD chains lose constant forwarding and the
-- encoder ends up reusing stale initial-table content.
local function resolve_const_str(op, ctx)
    if op:is_str() then
        return op:get_str()
    elseif op:is_ssa() then
        return ctx.const_strs[op:get_ssa()]
    end
    return nil
end

local function trim(str)
  if str == nil then return end
  local res = string_gsub(str, '^%s*(.-)%s*$', '%1')
  return res
end

-- The function checks that the file exists at the path passed to
-- the function. Returns true and file handle if file exists and
-- false otherwise.
local function file_exists(path)
    local ok, fh = pcall(io.open, path, "r")
    if ok and fh ~= nil then
        return true, fh
    end
    return false
end

-- Returns the solver backends in the order they should be tried.
-- The backend selected by LJOPT_SMT (cvc5 by default) goes first,
-- then the other one.
local function solver_backends()
    local preferred = ljopt_config.get_smt_solver()
    if preferred == "cvc5" then
        return {"cvc5", "z3"}
    elseif preferred == "z3" then
        return {"z3", "cvc5"}
    end
    return {"cvc5", "z3"}
end

-- Returns a solver instance or nil when no usable solver is
-- found. A backend whose library is missing or too old fails its
-- probe and is skipped.
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

-- Traces are reported (and selectable by) their position in the
-- list sorted by the source location they start at.
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

-- Returns the trace numbers sorted by the source location they
-- start at.
local function build_order(traces, trace_locs)
    local order = {}
    for traceno in pairs(traces) do
        table.insert(order, traceno)
    end
    table.sort(order, function(a, b)
        return loc_less(
            trace_locs[a] or tostring(a), trace_locs[b] or tostring(b)
        )
    end)
    return order
end

-- Returns the traces to check as {idx = pos, uid = traceno}
-- records. With a trace number only that trace is returned.
local function select_traces(order, trace_number)
    local selected = {}
    for pos, traceno in ipairs(order) do
        if trace_number == nil or pos == trace_number then
            table.insert(selected, {idx = pos, uid = traceno})
        end
    end
    return selected
end

local function rjust(n, width)
    local s = tostring(n)
    return string.rep(" ", width - #s) .. s
end

-- Wall-clock source, uses CLOCK_MONOTONIC through FFI.
local function clock_monotonic()
    local ts = ffi.new("ljopt_timespec")
    local time = ffi.C.clock_gettime(1, ts)
    if time == 0 then
        return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
    end
end

-- Dots of every result line reach this column, so the verdict and
-- time columns line up across traces with different locations.
local RESULT_COLUMN = 62

-- Parses and checks one trace formula. The Start line is printed
-- before the solver call so the user sees progress during a long
-- check. Returns the verdict string, a lowercase status and the
-- time the check took.
local function check_trace(solver, traces, traceno, idx, loc, widths)
    local smt_constants = require("ljopt.smt_constants")
    local start_tag = rjust(idx, widths.tag_w)
    io.stdout:write(string.rep(" ", widths.counter_w) ..
        ("Start %s:  %s\n"):format(start_tag, loc))
    io.stdout:flush()
    local smt_formula = smt_constants.LJOPT_SMTLIB .. traces[traceno]
    assert(solver:parse(smt_formula) == true)
    local solve_start = clock_monotonic()
    local check_res = solver:check(smt_formula)
    local solve_time = clock_monotonic() - solve_start
    if check_res == solver.result.SAT then
        return "Failed", "failed", solve_time
    elseif check_res == solver.result.UNKNOWN then
        return "Timeout", "timeout", solve_time
    end
    return "Passed", "passed", solve_time
end

-- Prints the "N/M Trace #N .... verdict time" line for one trace.
local function print_trace_line(idx, n_traces, loc, verdict,
                                solve_time, widths)
    local prefix = rjust(idx, widths.nw) .. "/" .. n_traces .. " "
        .. "Trace " .. rjust("#" .. idx, widths.tag_w) .. ":  " .. loc
    local dots = RESULT_COLUMN - #prefix
    if dots < 1 then dots = 1 end
    io.stdout:write(prefix .. string.rep(".", dots) ..
        ("   %-10s%.2f sec\n"):format(verdict, solve_time))
    io.stdout:flush()
end

-- Prints the verification summary and the failed/timed-out lists.
local function print_report(n_passed, n_failed, n_timed_out,
                            failed_list, timeout_list, n_checked,
                            start_time)
    io.stdout:write("\n")
    local passed_pct = math.floor(100 * n_passed / n_checked)
    if n_timed_out > 0 then
        io.stdout:write(("%d%% traces passed, %d traces failed, "
            .. "%d traces timed out out of %d\n")
            :format(passed_pct, n_failed, n_timed_out, n_checked))
    else
        io.stdout:write(("%d%% traces passed, %d traces failed out of %d\n")
            :format(passed_pct, n_failed, n_checked))
    end
    io.stdout:write("\n")
    io.stdout:write(("Total verification time (real) = %6.2f sec\n")
        :format(clock_monotonic() - start_time))
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
end

-- Checks the given traces one by one, printing a line per trace,
-- then prints the summary. Returns an exit code.
local function verify_traces(solver, traces, trace_locs, checked,
                             n_traces, start_time, exit_codes)
    local n_passed = 0
    local n_failed = 0
    local n_timed_out = 0
    local failed_list = {}
    local timeout_list = {}
    local widths = {nw = #("%d"):format(n_traces)}
    widths.counter_w = 2 * widths.nw + 2
    widths.tag_w = widths.nw + 1
    for _, item in ipairs(checked) do
        local idx = item.idx
        local traceno = item.uid
        local loc = trace_locs[traceno] or tostring(traceno)
        local verdict, status, solve_time =
            check_trace(solver, traces, traceno, idx, loc, widths)
        if status == "failed" then
            n_failed = n_failed + 1
            table.insert(failed_list, {idx = idx, loc = loc})
        elseif status == "timeout" then
            n_timed_out = n_timed_out + 1
            table.insert(timeout_list, {idx = idx, loc = loc})
        else
            n_passed = n_passed + 1
        end
        print_trace_line(idx, n_traces, loc, verdict, solve_time, widths)
    end
    print_report(n_passed, n_failed, n_timed_out, failed_list,
                 timeout_list, #checked, start_time)
    if n_failed > 0 then
        return exit_codes.ERR_VERIFICATION_FAILED
    elseif n_timed_out > 0 then
        return exit_codes.ERR_SMT_UNKNOWN
    end
    return exit_codes.OK
end


return {
    build_order = build_order,
    check_trace = check_trace,
    clock_monotonic = clock_monotonic,
    debug_msg = debug_msg,
    enrich_snapshots_with_exits = enrich_snapshots_with_exits,
    fatal_msg = fatal_msg,
    file_exists = file_exists,
    find_solver = find_solver,
    hash = fnv1a_hash,
    join_strings = join_strings,
    loc_key = loc_key,
    loc_less = loc_less,
    merge_tables = merge_tables,
    print_report = print_report,
    print_trace_line = print_trace_line,
    resolve_const = resolve_const,
    resolve_const_str = resolve_const_str,
    rjust = rjust,
    select_traces = select_traces,
    solver_backends = solver_backends,
    trim = trim,
    unreachable = unreachable,
    verify_traces = verify_traces,
}
