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
                -- Cdata refs are `int-val` cells (not `tab-val`):
                -- the 'cdt' load decodes the signed BV slot
                -- instead of calling `get-tab` on the wrong
                -- constructor.
                local tab_left = ctx.op_stack:load(value_data, 'cdt')
                local tab = ctx.mem_stack:load(tab_left)
                smt_expr = "; Cdt, use directly"
                slot_values[slot] = tab
            elseif type == "fun" then
                -- SLOADFun stores (tab-val mem_slot) in op_stack
                -- (no fun-val constructor in MemCell). Falling
                -- through to the numeric branch below would call
                -- get-fp on a tab-val cell — unconstrained, so
                -- z3 picks different fps cross-side and the snap
                -- equiv check spuriously sats. Treat fun like a
                -- table: compare the cell tied to
                -- shared[inherited_from][0] by allocate.
                local fun_ref = ctx.op_stack:load(value_data, op_type.TAB)
                local fun_content = ctx.mem_stack:load(fun_ref)
                smt_expr = "; Fun, use directly"
                slot_values[slot] = fun_content
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
                elseif type == "i64" or type == "u64"
                    or type == "u32" or type == "i8" or type == "u8"
                    or type == "i16" or type == "u16" then
                    -- Full 64-bit value -> fp (smt_int_to_fp would
                    -- truncate to 32 bits). Deterministic, so a
                    -- folded i64 constant and a computed i64 slot
                    -- compare equal; only distinct 64-bit results
                    -- that round to the same double are missed.
                    --
                    -- Every other C integer width belongs here too:
                    -- they all live as 64-bit BVs in an `int-val`
                    -- cell (a narrow XLOAD arrives already sign- or
                    -- zero-extended). Letting them fall through to
                    -- the numeric branch called get-fp on an
                    -- int-val cell, which is unconstrained, so z3
                    -- picked different fps per side and the check
                    -- sat spuriously -- the same trap as `fun`
                    -- above. It made 15 of 40 xmem traces read as
                    -- bug candidates on clean LuaJIT.
                    data = arith_utils.smt_i64_to_fp(
                        ctx.op_stack:load(value_data, op_type.I64)
                    )
                elseif type == "flt" then
                    -- float32 is held as (_ FloatingPoint 8 24);
                    -- widen it to the double the snap stack stores
                    -- rather than reading it as one.
                    data = ('((_ to_fp 11 53) RNE %s)'):format(
                        ctx.op_stack:load(value_data, 'flt')
                    )
                else
                    data = ctx.op_stack:load(value_data, op_type.NUM)
                end
                smt_expr = ctx.snap_stack:store(slot, op_type.NUM, data)
                slot_values[slot] = ctx.snap_stack:load(slot, op_type.NUM)
            end
        elseif value_type == "const"
            and pair[2].const_type == "string" then
            -- A folded string constant. The snap stack holds
            -- `num`, so it cannot carry one; pass the literal
            -- straight into the slot, exactly as the str-typed
            -- SSA branch above passes its String through.
            smt_expr = "; const str, use directly"
            slot_values[slot] = value_data
        elseif value_type == "const" then
            if value_data == "true" or value_data == "false" then
                -- Encode `true` and `false` as 1.0 and 0.0 to be
                -- consistent with fp <-> int narrowing
                -- optimizations (even though there's no
                -- fp <-> bool yet).
                value_data = arith_utils.const_num_to_smt_fp(
                    value_data == "true"
                )
            elseif pair[2].const_type == "i64" then
                -- i64 constant output: value-convert the 64-bit BV,
                -- matching the i64 SSA path so a folded constant and
                -- a computed i64 slot compare equal.
                value_data = arith_utils.smt_i64_to_fp(value_data)
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
