-- Loop unrolling transform for raw trace nodes.
-- Operates on raw node tables:
-- {num, flags, irtype, irop, op1,op2}
-- before construct_nodes(), so LOOP/PHI don't have IR
-- implementations.
--
-- Also duplicates body snapshots per iteration with remapped
-- nins and slot SSA refs, so that snapshot matching works
-- correctly after unrolling.

local dev_checks = require('ljopt.dev_checks')
local ljopt_config = require('ljopt.config')
local op_type = require('ljopt.ir.op_type')
local utils = require('ljopt.utils')
local arith_utils = require('ljopt.ir.arith_utils')

-- Some huge value to distinguish snapshots from different loop
-- iterations.
local SNAPSHOT_INC = 1e6

-- The remap table maps an SSA ref to the value that replaces it
-- in a copy: {tab = <operand>, txt = <display text>}, the same
-- pair a call argument is stored as. The value is a ref of the
-- copy or a constant a PHI folded to.
local function ssa_value(ref)
    return {tab = {type = 'ssa', value = ref}}
end

-- Remap an operand through the remap table. Returns the new
-- operand and its display text.
--
-- The display text records the operand as the *original* body
-- node spelled it, and op_type.to_string() prefers it over the
-- value. Once an SSA operand is remapped that text is stale, so
-- it is replaced by the text of the new value, which is only set
-- for a constant: that is where the SMT literal of a KNUM lives.
-- Literals (mode flags, field names) keep their text, since
-- op_type.from_raw() needs it to reconstruct them.
local function remap_value(operand, txt, remap)
    if operand == nil then
        return nil, txt
    end
    -- A call's argument list carries SSA refs of its own, one
    -- level down. Without recursing, a cloned CALL keeps reading
    -- the first iteration's arguments.
    if operand.type == 'carg' then
        local args = {}
        for i, arg in ipairs(operand.value) do
            local tab, arg_txt = remap_value(arg.tab, arg.txt, remap)
            args[i] = {tab = tab, txt = arg_txt}
        end
        return {type = 'carg', value = args}, txt
    end
    if operand.type ~= 'ssa' then
        return operand, txt
    end
    local value = remap[operand.value]
    if value == nil then
        return operand, nil
    end
    return value.tab, value.txt
end

-- Remap snapshot slot SSA refs using the iteration's remap table.
local function remap_snap_slots(slots, remap)
    local new_slots = {}
    for _, slot in ipairs(slots) do
        local info = slot[2]
        local value = (info.type == 'ssa' or info.type == 'softfp')
            and remap[info.value]
        if value and value.tab.type == 'number' then
            table.insert(new_slots, {slot[1], {
                type = 'const',
                const_type = 'number',
                value = arith_utils.const_num_to_smt_bv(value.tab.value),
            }})
        elseif value then
            table.insert(new_slots,
                {slot[1], {type = info.type, value = value.tab.value}}
            )
        elseif info.type == 'ssa' or info.type == 'softfp' then
            table.insert(new_slots, slot)
        else
            assert(info.type == 'const',
                ('unexpected snapshot slot type %s'):format(
                    tostring(info.type)
                )
            )
            table.insert(new_slots, slot)
        end
    end
    return new_slots
end

-- Build phi_map: prologue_ref -> the value the loop carries
-- into the next iteration. It is the PHI's right operand: a
-- body ref or a number the body value folded to.
local function infer_phi_map_opt(phi_nodes)
    local phi_map = {}
    for _, phi in ipairs(phi_nodes) do
        local prologue_ref = phi.op1 and phi.op1.type == 'ssa' and phi.op1.value
        local next_value = phi.op2
        if prologue_ref and next_value ~= nil
            and (next_value.type == 'ssa' or next_value.type == 'number') then
            phi_map[prologue_ref] = {tab = next_value, txt = phi.op2_txt}
        end
    end
    return phi_map
end

local function slots_at_snapshot(snap)
    local current = {}
    for _, slot in ipairs(snap.last_slots or {}) do
        current[slot[1]] = slot[2]
    end
    local out = {}
    for _, slot in ipairs(snap.slots) do
        table.insert(out, {slot[1], current[slot[1]] or slot[2]})
    end
    return out
end

local function clone_node(id, bnode, remap)
    local op1, op1_txt = remap_value(bnode.op1, bnode.op1_txt, remap)
    local op2, op2_txt = remap_value(bnode.op2, bnode.op2_txt, remap)
    return {
        num = id,
        flags = bnode.flags,
        irtype = bnode.irtype,
        irop = bnode.irop,
        op1 = op1,
        op2 = op2,
        op1_txt = op1_txt,
        op2_txt = op2_txt,
    }
end

local function clone_snap(new_nins, slots, remap)
    local new_slots = remap_snap_slots(slots, remap)

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
        if #snap.nins > 0 then
            local max_nins = math.max(unpack(snap.nins))
            if max_nins > final_max_nins then
                final_max_nins = max_nins
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

local function sload_slot_map(raw_nodes)
    local by_slot, narrowed = {}, {}
    for _, node in ipairs(raw_nodes) do
        if node.irop == 'SLOAD' or node.irop == 'SLOAD ' then
            local slot = node.op1 and node.op1.value
            if slot ~= nil then
                by_slot[slot] = node.num
                if node.irtype == 'int'
                    and (node.op2_txt or ''):find('C', 1, true) then
                    narrowed[slot] = true
                end
            end
        end
    end
    return by_slot, narrowed
end

-- Unroll a loop trace that has explicit LOOP/PHI markers.
-- Trace structure: prologue | LOOP | body | PHI nodes.
-- Output: prologue + N copies of body with remapped SSA refs.
local function unroll_with_loop_marker(raw_nodes, snapshots, loop_idx,
                                       op_stack)
    -- Partition into prologue, body, phi_nodes.
    local prologue = {}
    for i = 1, loop_idx - 1 do
        table.insert(prologue, raw_nodes[i])
    end
    local prologue_len = table.getn(prologue)
    local loop_num = raw_nodes[loop_idx].num

    local body = {}
    local body_orig_num = {}
    local phi_nodes = {}
    for i = loop_idx + 1, table.getn(raw_nodes) do
        if raw_nodes[i].irop == 'PHI' then
            table.insert(phi_nodes, raw_nodes[i])
        else
            table.insert(body, raw_nodes[i])
            table.insert(body_orig_num, raw_nodes[i].num)
        end
    end
    local body_len = table.getn(body)

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
                if nins >= loop_num then
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

    -- Build orig_num -> body_index lookup for nins remapping.
    local body_offset_by_num = {}
    do
        local last_num = raw_nodes[table.getn(raw_nodes)].num
        local offset = 1
        for num = loop_num, last_num do
            while offset < body_len
                and body_orig_num[offset + 1] <= num do
                offset = offset + 1
            end
            body_offset_by_num[num] = offset
        end
    end

    local function nins_to_body_offset(nins)
        return body_offset_by_num[nins] or body_len
    end

    local result = {}
    for _, node in ipairs(prologue) do
        table.insert(result, node)
    end

    local n = ljopt_config.get_loop_unroll_limit()
    local prev_phi_remap = {}

    local smt = ''
    local function precondition(ref)
        local iv = op_stack:load(ref, op_type.INT)
        smt = smt .. ('(assert (= %s ((_ sign_extend 32) ' ..
            '((_ extract 31 0) %s))))\n'):format(iv, iv)
    end
    local _, narrowed = sload_slot_map(raw_nodes)
    local narrowed_phi = {}
    if op_stack ~= nil and next(narrowed) ~= nil then
        for prologue_ref, next_value in pairs(phi_map) do
            if next_value.tab.type == 'ssa' then
                narrowed_phi[next_value.tab.value] = true
                precondition(prologue_ref)
            end
        end
    end

    for iter = 1, n do
        local remap = {}
        local base_pos = prologue_len + (iter - 1) * body_len
        for j, bnode in ipairs(body) do
            remap[bnode.num] = ssa_value(base_pos + j)
        end

        for prologue_ref, prev_value in pairs(prev_phi_remap) do
            remap[prologue_ref] = prev_value
        end

        for j, bnode in ipairs(body) do
            local cloned = clone_node(base_pos + j, bnode, remap)
            table.insert(result, cloned)
        end

        for body_ref in pairs(narrowed_phi) do
            if remap[body_ref] then
                precondition(remap[body_ref].tab.value)
            end
        end

        if snapshots then
            for _, snap_id in ipairs(body_snap_ids) do
                local snap = snapshots[snap_id]

                local new_nins = {}
                for _, nins in ipairs(snap.nins) do
                    if nins >= loop_num then
                        local body_offset = nins_to_body_offset(nins)
                        table.insert(new_nins,
                            prologue_len + (iter - 1) * body_len
                                + body_offset
                        )
                    end
                end

                local uid = snap_id + iter * SNAPSHOT_INC
                new_snapshots[uid] = clone_snap(
                    new_nins, slots_at_snapshot(snap), remap
                )
            end
        end

        -- The next copy enters with the values this copy carries.
        prev_phi_remap = {}
        for prologue_ref, next_value in pairs(phi_map) do
            local tab, txt = remap_value(next_value.tab, next_value.txt,
                remap)
            prev_phi_remap[prologue_ref] = {tab = tab, txt = txt}
        end
    end

    return result, new_snapshots, smt
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

    local n = ljopt_config.get_loop_unroll_limit()

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
        prev_phi_remap[sload_ref] = ssa_value(body_ref)
    end

    -- Produce N more copies (iterations 2..N+1) to match opt's
    -- prologue + N body copies = N+1 total iterations.
    for iter = 2, n + 1 do
        local remap = {}
        local base_pos = (iter - 1) * body_len
        for j, bnode in ipairs(body) do
            remap[bnode.num] = ssa_value(base_pos + j)
        end

        -- Connect iteration inputs via inferred phi_map.
        for prologue_ref, prev_value in pairs(prev_phi_remap) do
            remap[prologue_ref] = prev_value
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

    return result, new_snapshots
end

-- Main entry point. Dispatches to the appropriate
-- unrolling strategy.
--
-- @param raw_nodes  array of raw node tables
-- @param snapshots  snapshot table from trace_record
-- @param linktype   trace linktype ('loop', 'return', etc.)
local function loop_unrooling_transform(raw_nodes, snapshots, linktype,
                                        op_stack)
    dev_checks('table', '?table', '?string', '?table')

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
        return unroll_with_loop_marker(raw_nodes, snapshots, loop_idx,
            op_stack)
    elseif linktype == 'loop' then
        -- unoptimized trace.
        return unroll_without_loop_marker(raw_nodes, snapshots)

    end
    return raw_nodes, snapshots
end

return {
    loop_unrooling_transform = loop_unrooling_transform,
}
