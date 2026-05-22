-- IR analysis passes that run between node construction and
-- SMT-LIB emission.

------------------------------------------------------------------

-- Mark guards introduced by LJ's narrower as preconditions:
-- TEStackBV.store lifts them to top-level asserts so they don't
-- show up in the snap exit bitvector (where they'd produce a
-- spurious te-diff against unopt, which has no analogous IR).
local function mark_narrowed_refs(nodes, ctx)
    local marked = ctx.te_stack.narrowed_refs
    local sload_c = {}
    local function op_is_sload_c_or_const(op)
        if op == nil then return true end
        if op:is_ssa() then return sload_c[op:get_ssa()] == true end
        return true
    end

    -- Guard ops the LJ narrower emits in trace prologue. All four
    -- prologue-guard patterns from lj_record.c:rec_for_loop and
    -- lj_record.c:rec_for_check fall in
    -- this set:
    --   * `int LE/GE op_C CONST` (FORL const stop/step bound)
    --   * `int LT/GE op_C 0` (FORL direction guard)
    --   * `int ADDOV op_C op_C` (FORL stop+step overflow)
    -- We don't propagate through derived ops: LJ-emitted
    -- narrowing guards always have SLOAD-C or constant *direct*
    -- operands.
    local NARROWING_GUARD = {
        LE = true, LT = true, GE = true, GT = true,
        EQ = true, NE = true,
        ULE = true, ULT = true, UGE = true, UGT = true,
        ADDOV = true, SUBOV = true, MULOV = true,
        ABC = true,
    }

    for i = 1, table.getn(nodes) do
        local n = nodes[i]
        local sref = n:get_ssa_reference()
        if sref ~= nil then
            local l_op = n:get_left_op()
            local r_op = n:get_right_op()
            local opcode = n:get_opcode()
            if opcode == 'SLOAD' then
                local mode = r_op and r_op:get_lit() or ''
                if mode:find('C', 1, true) then
                    sload_c[sref] = true
                end
            elseif NARROWING_GUARD[opcode] and n:get_type() == 'int' then
                if op_is_sload_c_or_const(l_op) and
                   op_is_sload_c_or_const(r_op) and
                   (l_op:is_ssa() or r_op:is_ssa()) then
                    marked[sref] = true
                end
            end
        end
    end
end

return {
    mark_narrowed_refs = mark_narrowed_refs,
}
