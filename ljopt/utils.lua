local ljopt_config = require("ljopt.config")

local function debug_msg(s)
    if ljopt_config.is_debug_mode() then
        io.stderr:write(s .. "\n")
    end
end

local function unreachable(s)
    assert(false, s)
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
local function enrich_snapshots_with_exits(trace_record)
    local ins2snap = {}
    for uid, ins_snap in pairs(trace_record.snapshots) do
        trace_record.snapshots[uid].exits = {}
        for _, nins in ipairs(ins_snap.nins) do
            table.insert(ins2snap, {nins = nins, uid = uid})
        end
    end
    table.sort(ins2snap, function(a, b)
        return a.nins < b.nins
    end)
    local cur_snap_id = 1
    for ir_id, ir_node in pairs(trace_record.trace) do
        if (ir_node ~= nil and ir_node.flags.irt_guard) then
            -- Search for associated snapshot.
            while (#ins2snap >= cur_snap_id + 1 and
                   ins2snap[cur_snap_id + 1].nins <= ir_id) do
                cur_snap_id = cur_snap_id + 1
            end
            if (ins2snap[cur_snap_id].nins <= ir_id) then
                local snap_uid = ins2snap[cur_snap_id].uid
                table.insert(trace_record.snapshots[snap_uid].exits, ir_id)
                debug_msg(("Snapshot %d depends on %d"):format(
                    ins2snap[cur_snap_id].nins, ir_id
                ))
            end
        end
    end
end

return {
    debug_msg = debug_msg,
    merge_tables = merge_tables,
    enrich_snapshots_with_exits = enrich_snapshots_with_exits,
    unreachable = unreachable,
}
