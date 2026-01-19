-- Translate IR to SMT-LIB.
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR
-- luacheck: push no max_comment_line_length
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations#ssa-ir-optimizations
-- luacheck: pop

local jit = require('jit')

local ir_node = require('ljopt.ir.ir_nodes')
local dump_ir = require('ljopt.ir_dump')
local smt = require('ljopt.smtlib2').new()
local smt_context = require('ljopt.ir.smt_context')
local dev_checks = require('ljopt.dev_checks')
local smt_snapshot = require('ljopt.ir.SNAP')
local utils = require('ljopt.utils')

-- Documentation: https://luajit.org/running.html
local lj_unoptimized = "jit.opt.start(0, 'hotloop=1', 'hotexit=1')"
local lj_optimized = "jit.opt.start(3, 'hotloop=1', 'hotexit=1')"

local is_debug = os.getenv('LJOPT_DEBUG')

local dev_trace_dump = function() end

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ',\n'
        end
        return s .. '} '
    else
        return '"' .. tostring(o) .. '"'
    end
end

if os.getenv('LJOPT_DEBUG') then
    dev_trace_dump = dump
end

local function construct_nodes(trace)
    dev_checks('table')

    local nodes_table = {}
    for i = 1, table.getn(trace) do
        nodes_table[i] = ir_node.instance(
            string.format("%04d", trace[i].num),
            trace[i].flags,
            trace[i].irtype,
            trace[i].irop,
            trace[i].op1,
            trace[i].op2
        )
    end
    return nodes_table
end

-- Nodes transformers.
local function identity_transform(nodes)
    dev_checks('table')

    return nodes
end

local function loop_unrooling_transform(nodes)
    dev_checks('table')

    return nodes -- TODO: Implement.
end

local function function_inlining_transform(nodes)
    dev_checks('table')

    return nodes -- TODO: Implement.
end

local all_node_transforms = {
    identity_transform = identity_transform,
    function_inlining_transform = function_inlining_transform,
    loop_unrooling_transform = loop_unrooling_transform
}

local function transform_nodes(nodes)
    dev_checks('table')

    for i = 1, table.getn(all_node_transforms) do
        nodes = all_node_transforms[i](nodes)
    end

    return nodes
end

local vm_stack_prefix = 'vm_'
local op_stack_prefix = 'op_'
local te_stack_prefix = 'te_'
local snap_stack_prefix = 'snap_'

-- Translates single trace + snapshots into
-- SMT formula + fill SMTContext.
local function translate(trace_record, ctx_src, smt_suffix, tr_id)
    if (type(trace_record.trace) ~= 'table') then
        error('IR-dump is not a table')
    end

    if smt_suffix and type(smt_suffix) ~= 'string' then
        error('smt_suffix is not a string')
    end

    dev_trace_dump(trace_record.trace)

    local smtlib_buf = ''

    smt_suffix = smt_suffix or 'src'
    tr_id = tr_id or '0'
    ctx_src = ctx_src or smt_context.SMTContext:new('BV', 'BV')
    -- 0 stage. Create 'smt-context'.
    smtlib_buf = smtlib_buf ..
        ctx_src.op_stack:init_smt(op_stack_prefix .. smt_suffix .. tr_id) ..
        '\n'
    smtlib_buf = smtlib_buf ..
        ctx_src.te_stack:init_smt(te_stack_prefix .. smt_suffix .. tr_id) ..
        '\n'
    smtlib_buf = smtlib_buf ..
        ctx_src.snap_stack:init_smt(snap_stack_prefix .. smt_suffix .. tr_id) ..
        '\n'

    -- 1st stage. Constructing list of `ir_nodes`
    -- from raw string data.
    local nodes = construct_nodes(trace_record.trace)

    -- 2nd stage. Transformations (loop unrooling, function
    -- inlining, ...).
    nodes = transform_nodes(nodes)

    -- 3rd stage. Converting to SMT-LIB.
    for i = 1, table.getn(nodes) do
        local parsed_ir = (nodes[i]:get_ssa_reference() or '') .. ' '
            .. (nodes[i]:get_flags() or '') .. ' '
            .. (nodes[i]:get_type() or '') .. ' '
            .. (nodes[i]:get_opcode() or '') .. ' '
            .. (nodes[i]:get_left_op() or '') .. ' '
            .. (nodes[i]:get_right_op() or '') .. ' '

        smtlib_buf = ('%s%s ; %d   %s\n'):format(smtlib_buf,
            nodes[i]:to_smt_lib(ctx_src), i, parsed_ir)
    end
    -- 4th stage. Construct SNAPSHOTs
    local snap_nums = {}
    if trace_record.snapshots ~= nil then
        for i, snap in pairs(trace_record.snapshots) do
            local cur_sn, slot_values =
                smt_snapshot.snap_to_smt_lib(ctx_src, snap)
            smtlib_buf = smtlib_buf .. cur_sn .. '\n'
            snap_nums[i] = slot_values
        end
    end

    return smtlib_buf, snap_nums
end

local function trace2smt(trace, ctx, suffix, traceno)
    local tr_smtlib_unopt, snap_unopt = translate(trace, ctx, suffix, traceno)
    if (not tr_smtlib_unopt or #tr_smtlib_unopt == 0) then
        assert(not tr_smtlib_unopt or #tr_smtlib_unopt == 0,
            "Translation of trace failed, it shouldn't happen.")
    end
    return tr_smtlib_unopt, snap_unopt
end

local function snapshots2smt(snapshots1, snapshots2)
    local merged_snaps = utils.merge_tables(snapshots1, snapshots2)
    local smt_result = '(assert (or false\n'
    for _snap_id, values in pairs(merged_snaps) do
        local value1, value2 = unpack(values)
        if (value1 ~= nil) then
            local merged_snap = utils.merge_tables(value1, value2)
            for _slot_id, snap in pairs(merged_snap) do
                local val1, val2 = unpack(snap)
                smt_result =
                    ('%s    (not (= %s %s))\n'):format(smt_result, val1, val2)
            end
        end
    end
    smt_result = smt_result .. '))\n'
    return smt_result
end

-- Helper to record dump with the given optimization.
local function record_code(lua_code, opt)
    assert(load(opt))()
    -- Flush JIT so we'll have consistent
    -- trace numbers across recordings.
    jit.flush()
    local exec_records = dump_ir.record(lua_code, is_debug)
    assert(type(exec_records) == 'table')
    return exec_records
end

-- Runs Lua code twice with different level of optimizations
-- and translates obtained JIT traces to SMT-LIB formulas.
--
-- What's matter in formulas is the snapshot-related part,
-- it looks like
--
-- assert(not (snap1 = snap2))
--
-- Without snapshot related part formula is always SAT -
-- it's just a set of constraints stating valid states
-- of program during execution (and since execution
-- happened there's always at least one valid state).
--
-- When we add Snapshot comparison part this formula
-- becomes UNSAT, unless solver can find an input
-- where snap1 != snap2, which means these 2 traces
-- are not equivalent.
local function traces_to_smt(lua_code)
    local rec_unopt = record_code(lua_code, lj_unoptimized)
    if (is_debug) then
        print(string.rep('=', 60))
    end
    local rec_opt = record_code(lua_code, lj_optimized)

    assert(table.getn(rec_unopt) == table.getn(rec_opt),
        ('unmatched number of traces (%d vs %d)'):
            format(table.getn(rec_unopt), table.getn(rec_opt)))

    local traces_smtlib = {}
    for traceno in pairs(rec_unopt) do
        assert(rec_opt[traceno] ~= nil)
        local ctx_src = smt_context.SMTContext:new('BV', 'BV')
        local cur_trace =
            ctx_src.vm_stack:init_smt(vm_stack_prefix .. traceno) .. '\n'
        local trace_unopt, snaps_unopt =
            trace2smt(rec_unopt[traceno], ctx_src, 'unopt', traceno)
        local trace_opt, snaps_opt =
            trace2smt(rec_opt[traceno], ctx_src, 'opt', traceno)

        cur_trace = cur_trace .. trace_unopt .. '\n'
        cur_trace = cur_trace .. trace_opt .. '\n'

        -- Verify trace without SNAPshot constraints is parsable
        -- and SAT.
        assert(smt:parse(cur_trace))
        local smt_res = smt:check(cur_trace)
        assert(smt_res == smt.result.SAT or smt_res == smt.result.UNKNOWN)

        local smt_snapshots = snapshots2smt(snaps_unopt, snaps_opt)

        cur_trace = cur_trace .. smt_snapshots .. '\n'

        traces_smtlib[traceno] = cur_trace
    end
    return traces_smtlib, rec_unopt, rec_opt
end


-- Generates SMT formula that should be UNSAT (if optimizations
-- are correct).
local function translate_to_smt(lua_code)
    assert(load(lj_unoptimized))()
    local traces_formulas = traces_to_smt(lua_code)
    return traces_formulas
end

return {
    translate_to_smt = translate_to_smt,
    translate = translate,
    traces_to_smt = traces_to_smt,
}
