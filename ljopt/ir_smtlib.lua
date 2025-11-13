-- Translate IR to SMT-LIB.
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations#ssa-ir-optimizations

local ir_node = require('ljopt.ir.ir_nodes')
local dump_ir = require("ljopt.ir_dump")
local smt_context = require('ljopt.ir.smt_context')
local dev_checks = require('ljopt.dev_checks')
local smt_snapshot = require('ljopt.ir.SNAP')
local utils = require("ljopt.utils")

local lj_unoptimized = "jit.opt.start(0, '-fold', '+cse', '+fwd', 'hotloop=1', 'hotexit=1')"
local lj_optimized = "jit.opt.start(0, '+fold', '+cse', '+fwd', 'hotloop=1', 'hotexit=1')"


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

if os.getenv('LJOPT_ENABLE_DEBUG_LOGGING') then
    dev_trace_dump = dump
end

local function construct_nodes(trace)
    dev_checks('table')

    local nodes_table = {}
    for i = 1, #trace do
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

-- Translates single trace + snapshots into SMT formula + fill SMTContext
local function translate(trace, ctx_src, snapshot, smt_suffix, tr_id)
    dev_checks('table', 'table', '?string')

    if (type(trace) ~= 'table') then
        error('IR-dump is not a table')
    end

    dev_trace_dump(trace)

    local smtlib_buf = ""

    smt_suffix = smt_suffix or 'src'
    tr_id = tr_id or "0"
    ctx_src = ctx_src or smt_context.SMTContext:new('BV', 'BV')
    -- 0 stage. Create 'smt-context'.
    smtlib_buf = smtlib_buf .. ctx_src.op_stack:init_smt(op_stack_prefix .. smt_suffix .. tr_id) .. '\n'
    smtlib_buf = smtlib_buf .. ctx_src.te_stack:init_smt(te_stack_prefix .. smt_suffix .. tr_id) .. '\n'
    smtlib_buf = smtlib_buf .. ctx_src.snap_stack:init_smt(snap_stack_prefix .. smt_suffix .. tr_id) .. '\n'

    -- 1st stage. Constructing list of `ir_nodes` from raw string data.
    local nodes = construct_nodes(trace)

    -- 2nd stage. Transformations (loop unrooling, function inlining, ...).
    nodes = transform_nodes(nodes)

    -- 3rd stage. Converting to SMT-LIB.
    for i = 1, #nodes do
        local parsed_ir = (nodes[i]:get_ssa_reference() or '') .. ' '
            .. (nodes[i]:get_flags() or '') .. ' '
            .. (nodes[i]:get_type() or '') .. ' '
            .. (nodes[i]:get_opcode() or '') .. ' '
            .. (nodes[i]:get_left_op() or '') .. ' '
            .. (nodes[i]:get_right_op() or '') .. ' '

        smtlib_buf = smtlib_buf .. nodes[i]:to_smt_lib(ctx_src) .. ' ; ' .. i .. '   ' .. parsed_ir .. '\n'
    end
    -- 4th stage. Construct SNAPSHOTs
    local snap_nums = {}
    if snapshot ~= nil then
        for i, snap in pairs(snapshot) do
            local cur_sn, slot_values = smt_snapshot.snap_to_smt_lib(ctx_src, snap)
            smtlib_buf = smtlib_buf .. cur_sn .. "\n"
            snap_nums[i] = slot_values
        end
    end

    return smtlib_buf, snap_nums
end

-- Generates SMT formula that should be unsat (if optimizations are correct)
local function generate_smt_formula(lua_code, is_debug, add_check)
    assert(load(lj_unoptimized))()

    local traces_unopt, snapshots_unopt = dump_ir.record(lua_code, is_debug)
    assert(type(traces_unopt) == "table")
    assert(load(lj_optimized))()
    if (is_debug) then
        print("UNOPTIMIZED ==============================================")
    end
    local traces_opt, snapshots_opt = dump_ir.record(lua_code, is_debug)
    assert(type(traces_opt) == "table")

    if is_json and is_debug then
    local traces_buf = json.encode(traces)
    io.stdout:write(traces_buf .. "\n")
    end

    local traces_smtlib = [[
    (set-option :print-success false)
    (set-option :produce-models true)
    ]]

    for tr_n, tr_ir in pairs(traces_unopt) do
    local ctx_src = smt_context.SMTContext:new('BV', 'BV')
    traces_smtlib = traces_smtlib .. ctx_src.vm_stack:init_smt("vm_" .. tr_n) .. '\n'
    local tr_smtlib_unopt, snap_unopt = translate(tr_ir, ctx_src, snapshots_unopt[tr_n], "unopt", tr_n)
    local tr_smtlib_opt, snap_opt = translate(traces_opt[tr_n], ctx_src, snapshots_opt[tr_n], "opt", tr_n)

    if not tr_smtlib_unopt or #tr_smtlib_unopt == 0 or not tr_smtlib_opt or #tr_smtlib_opt == 0 then
        local msg = ("translation of trace %d to SMT-LIB has failed\n"):format(tr_n)
        io.stderr:write(msg)
        goto continue
    end
    traces_smtlib = traces_smtlib .. tr_smtlib_unopt .. "\n"
    traces_smtlib = traces_smtlib .. tr_smtlib_opt .. "\n"

    local merged_snaps = utils.merge_tables_named(snap_unopt, snap_opt)
    traces_smtlib = traces_smtlib .. "(assert (or false\n"
    for snap_id, values in pairs(merged_snaps) do
        local value1, value2 = values.value1, values.value2
        if (value1 ~= nil) then
        local merged_snap = utils.merge_tables_named(value1, value2)
        for slot_id, snap in pairs(merged_snap) do
            local val1, val2 = snap.value1, snap.value2
            traces_smtlib = traces_smtlib .. "    (not (= " .. val1 .. " " .. val2 .. "))\n"
        end
        end
    end
    traces_smtlib = traces_smtlib .. "))\n"
    if (add_check) then
        traces_smtlib = traces_smtlib .. "(check-sat)\n(get-model)\n(reset)\n" -- Check and reset current trace
    end
    ::continue::
    end
    return traces_smtlib
end

return {
    translate = translate,
    generate_smt_formula = generate_smt_formula,
}
