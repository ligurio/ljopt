-- Translate IR to SMT-LIB.
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR
-- luacheck: push no max_comment_line_length
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations#ssa-ir-optimizations
-- luacheck: pop

local ir_node = require('ljopt.ir.ir_nodes')
local ir_node_dummy = require('ljopt.ir.ir_node_dummy')
local op_type = require('ljopt.ir.op_type')
local runtime = require('ljopt.runtime')
local ljopt_config = require('ljopt.config')
local smt_context = require('ljopt.ir.smt_context')
local dev_checks = require('ljopt.dev_checks')
local smt_constants = require('ljopt.smt_constants')
local smt_snapshot = require('ljopt.ir.SNAP')
local utils = require('ljopt.utils')

-- Documentation: https://luajit.org/running.html
--
-- We disable `narrow` because sometimes it changes behaviour
-- of the trace, and we can't easily verify it.
-- See issue for tracking `narrow` implementation progress:
-- https://github.com/ligurio/ljopt/issues/34
local lj_unoptimized = "jit.opt.start(0, 'hotloop=1', 'hotexit=1')"
local lj_optimized = "jit.opt.start(3, 'hotloop=1', 'hotexit=1', '-narrow')"

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

if ljopt_config.is_debug_mode() then
    dev_trace_dump = dump
end

local function construct_nodes(trace)
    dev_checks('table')

    local nodes_table = {}
    local filtered_nodes = ir_node.get_nyi_nodes(trace.trace)
    if ljopt_config.is_strict_mode() and next(filtered_nodes) ~= nil then
        local err_msg = ''
        for i, _ in pairs(filtered_nodes) do
            err_msg = err_msg .. ' ' .. trace.trace[i].irop
        end
        io.stderr:write(
            'Ooopsie, some instructions is not implemented:' .. err_msg .. '.\n'
        )
        assert(false, 'Disable `strict` mode if you still want to verify it.')
    end
    for i = 1, table.getn(trace.trace) do
        local node = trace.trace[i]
        -- Convert raw {type, value} tables
        -- (from ir_dump_utils) to OpType objects.
        -- For literal-mode operands (field names,
        -- mode flags …) the raw table is nil but
        -- the text string is stored in op1_txt/op2_txt.
        local left_op  = op_type.from_raw(node.op1, node.op1_txt)
        local right_op = op_type.from_raw(node.op2, node.op2_txt)
        if filtered_nodes[i] == nil then
            table.insert(nodes_table, ir_node.instance(
                string.format('%04d', node.num),
                node.flags,
                node.irtype,
                node.irop,
                left_op,
                right_op
            ))
        else
            table.insert(nodes_table, ir_node_dummy.instance(node.irop):new(
                string.format('%04d', node.num),
                {
                    irt_guard=false,
                    raw=' '
                },
                node.irtype,
                node.irop .. 'dummy',
                left_op,
                right_op
            ))
        end
    end
    return nodes_table, filtered_nodes
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
local mem_stack_prefix = 'mem_'
local op_stack_prefix = 'op_'
local te_stack_prefix = 'te_'
local snap_stack_prefix = 'snap_'

-- Translates single trace + snapshots into
-- SMT formula + fill SMTContext.
local function translate(trace_record, ctx_src,
                         smt_suffix, tr_id, shared_stacks)
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
    if shared_stacks then
        -- Otherwise memory shouldn't be used.
        smtlib_buf = smtlib_buf ..
            ctx_src.mem_stack:init_smt(
                mem_stack_prefix .. smt_suffix .. tr_id, shared_stacks.mem_stack
            ) ..
            '\n'
    end
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
    local nodes, filtered_nodes = construct_nodes(trace_record)

    -- 2nd stage. Transformations (loop unrooling, function
    -- inlining, ...).
    nodes = transform_nodes(nodes)

    -- 3rd stage. Converting to SMT-LIB.
    jit.off(true, true)
    for i = 1, table.getn(nodes) do
        local parsed_ir = (nodes[i]:get_ssa_reference() or '') .. ' '
            .. (nodes[i]:get_flags().raw or '') .. ' '
            .. (nodes[i]:get_type() or '') .. ' '
            .. (nodes[i]:get_opcode() or '') .. ' '
            .. op_type.to_string(nodes[i]:get_left_op()) .. ' '
            .. op_type.to_string(nodes[i]:get_right_op()) .. ' '

        smtlib_buf = ('%s%s ; %d   %s\n'):format(smtlib_buf,
            nodes[i]:to_smt_lib(ctx_src), i, utils.trim(parsed_ir))
    end
    jit.on(true, true)
    -- 4th stage. Construct SNAPSHOTs
    local snap_nums = {}
    local failed = false
    if trace_record.snapshots ~= nil then
        local is_ok = utils.enrich_snapshots_with_exits(nodes, trace_record)
        if not is_ok then
            return smtlib_buf, {slots = {}, te = ""}, true
        end
        local ordered_snaps = {}
        for uid, ins_snap in pairs(trace_record.snapshots) do
            table.insert(ordered_snaps,
                {nins = ins_snap.nins[1], uid = uid}
            )
        end
        table.sort(ordered_snaps, function(a, b)
            return a.nins < b.nins
        end)
        for _, uid in ipairs(ordered_snaps) do
            local snap_id = uid.uid
            local snap = trace_record.snapshots[snap_id]
            local cur_sn, slot_values = smt_snapshot.snap_to_smt_lib(
                nodes, ctx_src, tr_id, snap_id, snap, filtered_nodes
            )
            smtlib_buf = smtlib_buf .. cur_sn .. '\n'
            snap_nums[snap_id] = slot_values
        end
        smtlib_buf = smtlib_buf .. ctx_src.snap_stack:finalize()
    end

    return smtlib_buf, {
        slots = snap_nums, te = ctx_src.snap_stack:load_te()
    }, failed
end

local function trace2smt(trace, ctx, suffix, traceno, shared_stacks)
    local tr_smtlib_unopt, snap_unopt, failed =
        translate(trace, ctx, suffix, traceno, shared_stacks)
    if (not tr_smtlib_unopt or #tr_smtlib_unopt == 0) then
        assert(not tr_smtlib_unopt or #tr_smtlib_unopt == 0,
            "Translation of trace failed, it shouldn't happen.")
    end
    return tr_smtlib_unopt, snap_unopt, failed
end

local function snapshots2smt(snapshots1, snapshots2, stack1, stack2)
    -- Sanity mode: drop the equivalence-check disjunct so the
    -- formula contains only the constraints accumulated during
    -- both traces. That formula must be SAT.
    if ljopt_config.is_verify_ljopt_correctness() then
        return ''
    end
    local merged_snaps = utils.merge_tables(snapshots1.slots, snapshots2.slots)
    -- Check whether both traces exited by a guard.
    local smt_result = ('(assert (or (not (= (lsb %s) (lsb %s)))\n'):format(
        snapshots1.te, snapshots2.te
    )
    smt_result = '(declare-const witness_ptr Int)\n' .. smt_result
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
    smt_result = smt_result .. '    ; Memory part\n'

    smt_result = smt_result .. ([[    (and (>= witness_ptr 0)
         (not (= (select (select %s %s) witness_ptr)
                 (select (select %s %s) witness_ptr))))
]]):format(
        stack1._name, stack1:get_version(),
        stack2._name, stack2:get_version()
    )
    smt_result = smt_result .. '))\n'
    return smt_result
end

-- Helper to record dump with the given optimization.
local function record_code(lua_code, opt)
    local exec_records = runtime.record_sandboxed(
        lua_code, opt, ljopt_config.is_debug_mode()
    )
    assert(type(exec_records) == 'table', 'Got type: ' .. type(exec_records))
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
    utils.debug_msg(string.rep('=', 60))
    local rec_opt = record_code(lua_code, lj_optimized)

    assert(table.getn(rec_unopt) == table.getn(rec_opt),
        ('unmatched number of traces (%d vs %d)'):
            format(table.getn(rec_unopt), table.getn(rec_opt)))

    local traces_smtlib = {}
    for traceno in pairs(rec_unopt) do
        if ljopt_config.is_strict_traces_matching() then
            assert(rec_opt[traceno] ~= nil, 'Unmatched trace ' ..
                traceno .. ' disable `LJOPT_STRICT` or ' ..
                '`LJOPT_STRICT_TRACE_MATCHING` if you want to ignore it.'
            )
        elseif rec_opt[traceno] == nil then
            goto continue
        end
        local shared_mem_stack = smt_context.MemoryStack:new()
        local shared_stacks = {mem_stack = shared_mem_stack}
        local cur_trace = shared_mem_stack:init_smt(
            'shared_mem_stack' .. traceno
        )
        local ctx_src = smt_context.SMTContext:new('BV', 'BV')
        cur_trace = cur_trace ..
            ctx_src.vm_stack:init_smt(vm_stack_prefix .. traceno) .. '\n'
        local trace_unopt, snaps_unopt, failed1 = trace2smt(
            rec_unopt[traceno], ctx_src, 'unopt', traceno, shared_stacks
        )
        -- Our ctx design is incorrect. We shouldn't
        -- share context between launches.
        local unopt_mem_stack = ctx_src.mem_stack
        ctx_src.mem_stack = smt_context.MemoryStack:new()
        ctx_src:restart()
        local trace_opt, snaps_opt, failed2 = trace2smt(
            rec_opt[traceno], ctx_src, 'opt', traceno, shared_stacks
        )
        local opt_mem_stack = ctx_src.mem_stack

        if failed1 or failed2 then
            io.stderr:write('Skip trace ' .. traceno .. '.\n')
            goto continue
        end

        cur_trace = cur_trace .. trace_unopt .. '\n'
        cur_trace = cur_trace .. trace_opt .. '\n'

        local smt_snapshots = snapshots2smt(
            snaps_unopt, snaps_opt, unopt_mem_stack, opt_mem_stack
        )

        cur_trace = cur_trace .. smt_snapshots .. '\n'

        traces_smtlib[traceno] = cur_trace
        ::continue::
    end
    return traces_smtlib
end


-- Generates SMT formula that should be UNSAT (if optimizations
-- are correct).
local function translate_to_smt(lua_code)
    assert(load(lj_unoptimized))()
    local traces_formulas = traces_to_smt(lua_code)

    local SMT_PREAMBLE = [[
(set-option :print-success false)
(set-option :produce-models true)
]] .. smt_constants.LJOPT_SMTLIB
    local traces_smtlib = ''

    -- Concatenate all traces
    for _, tr_smt in pairs(traces_formulas) do
        traces_smtlib = traces_smtlib .. SMT_PREAMBLE .. tr_smt
        -- Check current trace.
        traces_smtlib = traces_smtlib .. '(check-sat)\n'
        if ljopt_config.is_dump_model() then
            -- Print counterexample if found.
            traces_smtlib = traces_smtlib .. '(get-model)\n'
        end
        -- Reset, so next snapshots will be independent.
        traces_smtlib = traces_smtlib .. '(reset)\n'
    end
    return traces_smtlib
end

return {
    translate_to_smt = translate_to_smt,
    translate = translate,
    traces_to_smt = traces_to_smt,
    construct_nodes = construct_nodes,
}
