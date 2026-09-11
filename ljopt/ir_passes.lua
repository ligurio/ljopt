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
    -- Refs derived from a C-flagged (int-convertible) SLOAD via
    -- pure int arithmetic (or a constant). The narrower emits
    -- overflow guards on a *chain* of such arithmetic (e.g.
    -- SUBOV(SUBOV(0, i), k)); only the first guard's operands are
    -- the C-SLOAD directly, the later ones must be recognised
    -- through the derived refs below.
    local narrowed = {}

    local function op_derived(op)
        if op == nil then return true end
        if op:is_ssa() then return narrowed[op:get_ssa()] == true end
        return true
    end

    local function op_direct_c(op)
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
    local NARROWING_GUARD = {
        LE = true, LT = true, GE = true, GT = true,
        EQ = true, NE = true,
        ULE = true, ULT = true, UGE = true, UGT = true,
        ADDOV = true, SUBOV = true, MULOV = true,
        ABC = true,
    }

    -- Int value ops that propagate the narrowed-derived property
    -- from their operands to their result.
    local NARROW_DERIVED = {
        ADD = true, SUB = true, MUL = true, NEG = true,
        ADDOV = true, SUBOV = true, MULOV = true,
    }

    -- First pass: collect C-flagged SLOADs and propagate the
    -- narrowed-derived property through int arithmetic (defs
    -- precede uses in the IR, so one pass is a fixpoint).
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
                    narrowed[sref] = true
                end
            elseif NARROW_DERIVED[opcode] and n:get_type() == 'int' then
                if op_derived(l_op) and op_derived(r_op) then
                    narrowed[sref] = true
                end
            end
        end
    end

    -- Second pass: lift the narrowing guards to preconditions.
    for i = 1, table.getn(nodes) do
        local n = nodes[i]
        local sref = n:get_ssa_reference()
        if sref ~= nil then
            local l_op = n:get_left_op()
            local r_op = n:get_right_op()
            local opcode = n:get_opcode()
            if NARROWING_GUARD[opcode] and n:get_type() == 'int' then
                local has_ssa = (l_op ~= nil and l_op:is_ssa()) or
                    (r_op ~= nil and r_op:is_ssa())
                local direct = op_direct_c(l_op) and op_direct_c(r_op)
                -- A chained overflow guard (operands are derived
                -- int refs, not the C-SLOAD directly) can only
                -- fire for loop values outside the domain the
                -- narrower assumes, so treat it as a precondition
                -- too. Only overflow guards qualify: an EQ/LE on
                -- a derived ref is real control flow (loop exit).
                local derived_ov =
                    (opcode == 'ADDOV' or opcode == 'SUBOV' or
                     opcode == 'MULOV') and
                    op_derived(l_op) and op_derived(r_op)
                if has_ssa and (direct or derived_ov) then
                    marked[sref] = true
                end
            end
        end
    end
end

return {
    mark_narrowed_refs = mark_narrowed_refs,
}
