local function snap_to_smt_lib(ctx, snapshot)
    ctx.snap_stack:inc()
    local snap_data = {}      
    local slot_values = {} -- slot number -> SMT expression
    for _, pair in ipairs(snapshot) do
        local slot, value_type, value_data = pair[1], pair[2], pair[3]
        local smt_expr
        local type = "num"
        if value_type == "ssa" then
            smt_expr = ctx.snap_stack:store(slot, type, ctx.op_stack:load(value_data, type))
            slot_values[slot] = ctx.snap_stack:load(slot, type)
        elseif value_type == "const" then
            local cnst = string.format('((_ to_fp 11 53) RNE %s)', value_data)
            cnst = cnst:gsub('+', '')
            smt_expr = ctx.snap_stack:store(slot, type, cnst)  -- Convert constant to SMT
            slot_values[slot] = ctx.snap_stack:load(slot, type)
        elseif value_type == "softfp" then
            local ref2 = pair[4]
            local left = ctx.snap_stack:store(slot, type, ctx.op_stack:load(value_data, type))
            local right = ctx.snap_stack:store(slot + 1, type, ctx.op_stack:load(ref2, type))
            smt_expr = left .. right
        else
            error("unreachable")
        end
        table.insert(snap_data, smt_expr)
    end
    return table.concat(snap_data, "\n"), slot_values
end

return {
    snap_to_smt_lib = snap_to_smt_lib,
}
