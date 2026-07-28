-- Loop unrolling transform for raw trace nodes.
-- Operates on raw node tables:
-- {num, flags, irtype, irop, op1,op2}
-- before construct_nodes(), so LOOP/PHI don't have IR
-- implementations.
--
-- Also duplicates body snapshots per iteration with remapped
-- nins and slot SSA refs, so that snapshot matching works
-- correctly after unrolling.
--
-- Besides the nodes and snapshots, the transform reports the ref
-- at which the final unrolled iteration begins. Guards below it
-- must be forced true when emitting SMT: the trace we recorded
-- ran every one of these iterations, so had any earlier guard
-- failed the trace would have exited there and the later
-- iterations would never have stored anything. Leaving them free
-- lets the solver pick an input that exits on iteration 1 while
-- still comparing memory written by iterations 2..N, which is a
-- spurious sat (an int32-overflowing induction variable is the
-- easy witness). See `translate` in ljopt/ir_smtlib.lua.

local dev_checks = require('ljopt.dev_checks')
local ljopt_config = require('ljopt.config')
local utils = require('ljopt.utils')

-- Some huge value to distinguish snapshots from different loop
-- iterations.
local SNAPSHOT_INC = 1e6

-- Remap an operand's SSA reference if it appears in the
-- remap table.
local function remap_operand(operand, remap)
    if operand == nil or operand.type ~= 'ssa' then
        return operand
    end
    if remap[operand.value] then
        return {type = 'ssa', value = remap[operand.value]}
    end
    return operand
end

-- Remap snapshot slot SSA refs using the iteration's remap table.
local function remap_snap_slots(slots, remap)
    local new_slots = {}
    for _, slot in ipairs(slots) do
        local info = slot[2]
        if info.type == 'ssa' then
            local new_ref = remap[info.value] or info.value
            table.insert(new_slots,
                {slot[1], {type = 'ssa', value = new_ref}}
            )
        elseif info.type == 'softfp' then
            local new_ref = remap[info.value] or info.value
            table.insert(new_slots,
                {slot[1], {type = 'softfp', value = new_ref}}
            )
        else
            -- 'const' slots don't reference SSA refs.
            table.insert(new_slots, slot)
        end
    end
    return new_slots
end

local function infer_phi_map_opt(phi_nodes)
    local phi_map = {}
    for _, phi in ipairs(phi_nodes) do
        local prologue_ref = phi.op1 and phi.op1.type == 'ssa' and phi.op1.value
        local body_ref = phi.op2 and phi.op2.type == 'ssa' and phi.op2.value
        if prologue_ref and body_ref then
            phi_map[body_ref] = prologue_ref
        end
    end
    return phi_map
end


local function clone_node(id, bnode, remap)
    return {
        num = id,
        flags = bnode.flags,
        irtype = bnode.irtype,
        irop = bnode.irop,
        op1 = remap_operand(bnode.op1, remap),
        op2 = remap_operand(bnode.op2, remap),
        op1_txt = bnode.op1_txt,
        op2_txt = bnode.op2_txt,
    }
end

local function clone_snap(new_nins, slots, snap_remap)
    local new_slots = remap_snap_slots(slots, snap_remap)

    if #new_nins > 0 then
        return {nins = new_nins, slots = new_slots}
    else
        return nil
    end
end

-- Build phi_map for loop traces without LOOP/PHI markers.
-- Uses the final snapshot to infer which SLOAD inputs map
-- to which body outputs
-- (the values that feed back into the next iteration).
local function infer_phi_map_unopt(raw_nodes, snapshots)
    if not snapshots then return {} end

    -- Find the final snapshot (highest max nins).
    local final_snap = nil
    local final_max_nins = -1
    for _, snap in pairs(snapshots) do
        for _, nins in ipairs(snap.nins) do
            if nins > final_max_nins then
                final_max_nins = nins
                final_snap = snap
            end
        end
    end
    if not final_snap then return {} end

    -- Build slot_num -> SLOAD SSA ref mapping.
    local sload_by_slot = {}
    for _, node in ipairs(raw_nodes) do
        if node.irop == 'SLOAD' or node.irop == 'SLOAD ' then
            local slot = node.op1 and node.op1.value
            if slot then
                sload_by_slot[slot] = node.num
            else
                utils.unreachable('SLOT should have op1 non nil.')
            end
        end
    end

    -- Build phi_map: body_output_ref -> sload_ref.
    -- The final snapshot maps slot N -> SSA ref R. If there's
    -- a SLOAD for slot N, then R feeds back into SLOAD N.
    -- Use last_slots - last snapshots captures phi values.
    local phi_map = {}
    local phi_slots = final_snap.last_slots
    for _, slot_entry in ipairs(phi_slots) do
        local slot_num = slot_entry[1]
        local info = slot_entry[2]
        if info.type == 'ssa' then
            local body_output_ref = info.value
            local sload_ref = sload_by_slot[slot_num]
            if sload_ref and body_output_ref ~= sload_ref then
                phi_map[body_output_ref] = sload_ref
            end
        end
    end

    return phi_map
end

-- Unroll a loop trace that has explicit LOOP/PHI markers.
-- Trace structure: prologue | LOOP | body | PHI nodes.
-- Output: prologue + N copies of body with remapped SSA refs.
local function unroll_with_loop_marker(raw_nodes, snapshots, loop_idx)
    -- Partition into prologue, body, phi_nodes.
    local prologue = {}
    for i = 1, loop_idx - 1 do
        table.insert(prologue, raw_nodes[i])
    end
    local prologue_len = #prologue

    local body = {}
    local body_orig_pos = {}
    local phi_nodes = {}
    for i = loop_idx + 1, table.getn(raw_nodes) do
        if raw_nodes[i].irop == 'PHI' then
            table.insert(phi_nodes, raw_nodes[i])
        else
            table.insert(body, raw_nodes[i])
            table.insert(body_orig_pos, i)
        end
    end
    local body_len = #body

    -- Build phi_map: body_output_ref -> prologue_input_ref.
    local phi_map = infer_phi_map_opt(phi_nodes)

    -- Classify snapshots and split mixed ones.
    local new_snapshots = nil
    local body_snap_ids = {}
    if snapshots then
        new_snapshots = {}
        for snap_id, snap in pairs(snapshots) do
            local has_body = false
            local prologue_nins = {}
            for _, nins in ipairs(snap.nins) do
                if nins >= loop_idx then
                    has_body = true
                else
                    table.insert(prologue_nins, nins)
                end
            end
            if has_body then
                table.insert(body_snap_ids, snap_id)
                if #prologue_nins > 0 then
                    new_snapshots[snap_id] = {
                        nins = prologue_nins, slots = snap.slots
                    }
                end
            else
                new_snapshots[snap_id] = snap
            end
        end
    end

    -- Build orig_pos -> body_index lookup for nins remapping.
    local function nins_to_body_offset(nins)
        local best = 1
        for j = 1, body_len do
            if body_orig_pos[j] <= nins then
                best = j
            end
        end
        return best
    end

    local result = {}
    for _, node in ipairs(prologue) do
        table.insert(result, node)
    end

    local n = ljopt_config.get_loop_unroll_count()
    local prev_phi_remap = {}

    for iter = 1, n do
        local remap = {}
        local base_pos = prologue_len + (iter - 1) * body_len
        for j, bnode in ipairs(body) do
            remap[bnode.num] = base_pos + j
        end

        for prologue_ref, prev_ref in pairs(prev_phi_remap) do
            remap[prologue_ref] = prev_ref
        end

        for j, bnode in ipairs(body) do
            local cloned = clone_node(base_pos + j, bnode, remap)
            table.insert(result, cloned)
        end

        if snapshots then
            for _, snap_id in ipairs(body_snap_ids) do
                local snap = snapshots[snap_id]

                local new_nins = {}
                for _, nins in ipairs(snap.nins) do
                    if nins >= loop_idx then
                        local body_offset = nins_to_body_offset(nins)
                        table.insert(new_nins,
                            prologue_len + (iter - 1) * body_len
                                + body_offset
                        )
                    end
                end

                local snap_remap = {}
                for k, v in pairs(remap) do snap_remap[k] = v end
                for body_ref, prologue_ref in pairs(phi_map) do
                    snap_remap[prologue_ref] = remap[body_ref]
                end
                local uid = snap_id + iter * SNAPSHOT_INC
                new_snapshots[uid] = clone_snap(
                    new_nins, snap.slots, snap_remap
                )
            end
        end

        prev_phi_remap = {}
        for body_ref, prologue_ref in pairs(phi_map) do
            prev_phi_remap[prologue_ref] = remap[body_ref]
        end
    end

    -- Prologue + body copies 1..n-1 are known to have run.
    return result, new_snapshots, prologue_len + (n - 1) * body_len + 1
end

-- Unroll a loop trace that has NO LOOP/PHI markers
-- (opt level 0). The entire trace is one loop iteration.
-- PHI connections are inferred from the final snapshot which
-- maps stack slots to body output refs.
local function unroll_without_loop_marker(raw_nodes, snapshots)
    local body = raw_nodes
    local body_len = table.getn(body)
    local phi_map = infer_phi_map_unopt(raw_nodes, snapshots)

    utils.debug_msg('Inferred phi_map for loop without LOOP marker:')
    for body_ref, sload_ref in pairs(phi_map) do
        utils.debug_msg(('  %d -> %d'):format(body_ref, sload_ref))
    end

    -- Identify SLOADs that are PHI inputs (fed by previous
    -- iteration). These become dead in iterations 2+ and must be
    -- NOP'd to avoid spurious guards and SMT assertions.
    local phi_sloads = {}
    for _, sload_ref in pairs(phi_map) do
        phi_sloads[sload_ref] = true
    end

    local n = ljopt_config.get_loop_unroll_count()

    -- First copy: keep original nodes as-is.
    local result = {}
    for _, node in ipairs(body) do
        table.insert(result, node)
    end

    -- Snapshot handling: first copy keeps original snapshots,
    -- copies 2..N+1 get new uids.
    local new_snapshots = nil
    local snap_ids = {}
    if snapshots then
        new_snapshots = {}
        for snap_id, snap in pairs(snapshots) do
            new_snapshots[snap_id] = snap
            table.insert(snap_ids, snap_id)
        end
    end

    -- Build initial prev_phi_remap from iteration 1.
    local prev_phi_remap = {}
    for body_ref, sload_ref in pairs(phi_map) do
        prev_phi_remap[sload_ref] = body_ref
    end

    -- Produce N more copies (iterations 2..N+1) to match opt's
    -- prologue + N body copies = N+1 total iterations.
    for iter = 2, n + 1 do
        local remap = {}
        local base_pos = (iter - 1) * body_len
        for j, bnode in ipairs(body) do
            remap[bnode.num] = base_pos + j
        end

        -- Connect iteration inputs via inferred phi_map.
        for prologue_ref, prev_ref in pairs(prev_phi_remap) do
            remap[prologue_ref] = prev_ref
        end

        for j, bnode in ipairs(body) do
            local cloned = clone_node(base_pos + j, bnode, remap)
            -- Make NOP PHI-input SLOADs: their values come from
            -- the previous iteration via remap, so the SLOAD
            -- itself is dead.
            if phi_sloads[bnode.num] then
                cloned.irop = 'NOP'
                cloned.irtype = 'nil'
                cloned.flags = {irt_guard = false, raw = ' '}
                cloned.op1 = nil
                cloned.op2 = nil
                cloned.op1_txt = nil
                cloned.op2_txt = nil
            end
            table.insert(result, cloned)
        end

        if snapshots then
            for _, snap_id in ipairs(snap_ids) do
                local snap = snapshots[snap_id]

                local new_nins = {}
                for _, nins in ipairs(snap.nins) do
                    table.insert(new_nins, base_pos + nins)
                end

                local uid = snap_id + (iter - 1) * SNAPSHOT_INC
                new_snapshots[uid] = clone_snap(new_nins, snap.slots, remap)
            end
        end

        prev_phi_remap = {}
        for body_ref, sload_ref in pairs(phi_map) do
            prev_phi_remap[sload_ref] = remap[body_ref]
        end
    end

    -- Copies 1..n are known to have run; copy n+1 is the last.
    return result, new_snapshots, n * body_len + 1
end

-- Main entry point. Dispatches to the appropriate
-- unrolling strategy.
--
-- @param raw_nodes  array of raw node tables
-- @param snapshots  snapshot table from trace_record
-- @param linktype   trace linktype ('loop', 'return', etc.)
-- @return unrolled_nodes, updated_snapshots, last_iteration_ref
--         (`last_iteration_ref` is nil when nothing was
--          unrolled, i.e. every guard may legitimately fail)
local function loop_unrooling_transform(raw_nodes, snapshots, linktype)
    dev_checks('table', '?table', '?string')

    -- Find LOOP node position.
    local loop_idx = nil
    for i = 1, table.getn(raw_nodes) do
        if raw_nodes[i].irop == 'LOOP' then
            loop_idx = i
            break
        end
    end

    if loop_idx then
        -- optimized trace.
        return unroll_with_loop_marker(raw_nodes, snapshots, loop_idx)
    elseif linktype == 'loop' then
        -- unoptimized trace.
        return unroll_without_loop_marker(raw_nodes, snapshots)

    end
    return raw_nodes, snapshots
end

return {
    loop_unrooling_transform = loop_unrooling_transform,
}
