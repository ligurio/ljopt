local arith_utils = require("ljopt.ir.arith_utils")
local op_type = require("ljopt.ir.op_type")
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
        local slot = pair[1]
        local value_type = pair[2].type
        local value_data = pair[2].value
        local smt_expr
        if value_type == "ssa" then
            -- Write only if this value is implemented.
            if filtered_nodes[value_data] ~= nil then
                utils.debug_msg(
                    ("Ignore snapshot %s %s"):format(tr_id, snap_id)
                )
                goto continue
            end
            local type = trace[value_data]:get_type()
            if type == "tab" then
                local tab_left = ctx.op_stack:load(value_data, op_type.TAB)
                local tab = ctx.mem_stack:load(tab_left)
                smt_expr = "; Table, use directly"
                slot_values[slot] = tab
            elseif type == "cdt" then
                local tab_left = ctx.op_stack:load(value_data, op_type.TAB)
                local tab = ctx.mem_stack:load(tab_left)
                smt_expr = "; Cdt, use directly"
                slot_values[slot] = tab
            elseif type == "str" then
                local tab = ctx.op_stack:load(value_data, op_type.STR)
                smt_expr = "; str, use directly"
                slot_values[slot] = tab
            else
                local data
                if type == "int" then
                    data = arith_utils.smt_int_to_fp(
                        ctx.op_stack:load(value_data, op_type.I64)
                    )
                else
                    data = ctx.op_stack:load(value_data, op_type.NUM)
                end
                smt_expr = ctx.snap_stack:store(slot, op_type.NUM, data)
                slot_values[slot] = ctx.snap_stack:load(slot, op_type.NUM)
            end
        elseif value_type == "const" then
            if value_data == 'true' then
                value_data = '((_ to_fp 11 53) #x3FF0000000000000)'
            elseif value_data == 'false' then
                value_data = '((_ to_fp 11 53) #x0000000000000000)'
            else
                value_data = ('((_ to_fp 11 53) %s)'):format(value_data)
            end
            smt_expr = ctx.snap_stack:store(slot, 'num', value_data)
            slot_values[slot] = ctx.snap_stack:load(slot, 'num')
        elseif value_type == "softfp" then
            error("This path was not tested and never occured before.")
            local type = "num"
            local ref2 = value_data + 1
            local left = ctx.snap_stack:store(
                slot, type, ctx.op_stack:load(value_data, type))
            local right = ctx.snap_stack:store(
                slot + 1, type, ctx.op_stack:load(ref2, type))
            smt_expr = left .. right
        else
            utils.unreachable()
        end
        table.insert(snap_data, smt_expr)
        ::continue::
    end

    local e = nil
    if #snapshot.exits > 0 then
        e = ctx.te_stack:load(snapshot.exits[1])
        for i = 2, #snapshot.exits do
            local b = snapshot.exits[i]
            e = ('(and %s %s)'):format(ctx.te_stack:load(b), e)
        end
    end
    ctx.snap_stack:inc(snap_id, e, ctx)
    return table.concat(snap_data, "\n"), slot_values
end

return {
    snap_to_smt_lib = snap_to_smt_lib,
}
