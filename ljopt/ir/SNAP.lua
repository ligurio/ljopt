local utils = require("ljopt.utils")

-- Translate snapshot representation to SMT-LIB string.
-- We have snap_stack of type array<array<BV>>, where first index
-- is a number of snapshot, second index is snapshot values.
--
-- Example:
-- SNAP #2 [ ---- 0003 0004 ---- ---- 1.42 ]
-- Will be passed in input as:
-- [{1, ssa, 3}, {2, ssa, 4}, {5, const, "bv1068876431"} }
-- And this function will return:
-- [(1, "<smt formula>"),
--  (2, "<smt formula>"),
--  (5, "<smt formula>")]
--
-- More about snapshot representaion can be found here:
-- https://ujit.readthedocs.io/en/latest/public/tut-snap.html
-- @a snapshot output of ir_dump.
-- In format: array<(slot, value, optional_value)>
local function snap_to_smt_lib(trace, ctx, tr_id, snap_id,
                               snapshot, filtered_nodes)
    local snap_data = {}
    -- Slot number -> SMT expression.
    local slot_values = {}
    for _, pair in ipairs(snapshot.slots) do
        local slot, value_type, value_data = pair[1], pair[2], pair[3]
        local smt_expr
        local type = "num"
        if value_type == "ssa" then
            -- Write only if this value is implemented.
            if filtered_nodes[value_data] == nil then
                local op_type = trace[value_data]:get_type()
                local data = ctx.op_stack:load(value_data,op_type)
                if op_type == "int" then
                    data = string.format("((_ to_fp 11 53) %s)", data)
                end
                smt_expr = ctx.snap_stack:store(slot, type, data)
                slot_values[slot] = ctx.snap_stack:load(slot, type)
            else
                utils.debug_msg(
                    ("Ignore snapshot %s %s"):format(tr_id, snap_id)
                )
            end
        elseif value_type == "const" then
            if value_data == 'true' then
                -- 1.0 as float
                value_data = '#x3FF0000000000000'
            elseif value_data == 'false' then
                -- 0.0 as float
                value_data = '#x0000000000000000'
            end
            local cnst = ('((_ to_fp 11 53) %s)'):format(value_data)
            cnst = cnst:gsub('+', '')
            -- Convert constant to SMT.
            smt_expr = ctx.snap_stack:store(slot, type, cnst)
            slot_values[slot] = ctx.snap_stack:load(slot, type)
        elseif value_type == "softfp" then
            local ref2 = pair[4]
            local left = ctx.snap_stack:store(
                slot, type, ctx.op_stack:load(value_data, type))
            local right = ctx.snap_stack:store(
                slot + 1, type, ctx.op_stack:load(ref2, type))
            smt_expr = left .. right
            utils.unreachable(
                "This path was not tested and never occured before."
            )
        else
            utils.unreachable()
        end
        table.insert(snap_data, smt_expr)
    end

    local e = nil
    if #snapshot.exits > 0 then
        e = ctx.te_stack:load(snapshot.exits[1])
        for i = 2, #snapshot.exits do
            local b = snapshot.exits[i]
            e = ('(and %s %s)'):format(ctx.te_stack:load(b), e)
        end
    end
    ctx.snap_stack:inc(snap_id, tr_id, e, ctx)
    return table.concat(snap_data, "\n"), slot_values
end

return {
    snap_to_smt_lib = snap_to_smt_lib,
}
