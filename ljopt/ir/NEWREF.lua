local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local constants = require('ljopt.smt_constants')

local impls = {}

local ASIZE_ID = arith_utils.const_str_to_memcell(
    constants.FIELD_TAB_PREFIX .. 'tab.asize'
)
local HMASK_ID = arith_utils.const_str_to_memcell(
    constants.FIELD_TAB_PREFIX .. 'tab.hmask'
)

-- The Lua value of a constant key, or nil for a computed one.
-- Only a constant key can be followed by the size model: it is
-- what decides whether the key is already there and whether it
-- belongs in the array part.
--
-- A folded constant counts too, and has to: the optimized trace
-- often has the key as a literal where the unoptimized one still
-- computes it, and the two would otherwise disagree about the
-- sizes for no reason other than that.
local function const_key(op, ctx)
    if op:is_str() then
        return op:get_str()
    elseif op:is_num() then
        return op:get_num()
    elseif op:is_ssa() then
        return ctx.const_nums[op:get_ssa()]
    end
    return nil
end

-- The sizes an *empty* table has after one key is put into it.
-- lj_tab_newkey rehashes immediately, having no hash part to put
-- the key in, and lj_tab.c's bestasize() then takes an array part
-- only if the integer keys more than half fill a power of two:
-- for a single key that means 0, 1 or 2, giving an array of 3.
-- Every other key, integer or not, goes into a two-node hash.
local function sizes_after_first(key)
    if type(key) == 'number' and key == math.floor(key)
        and key >= 0 and key <= 2 then
        return 3, 0
    end
    return 0, 1
end

-- Inserting a key can rehash the table, which resizes both of
-- its parts. Both sizes are observable -- an ABC is checked
-- against tab.asize, and the recorder guards tab.hmask to prove
-- the hash part is still empty -- so the translation has to say
-- what the insertion did to them.
--
-- With the contents known (the table was allocated in this trace
-- and every key since was a constant) the new sizes are computed
-- exactly, the way lj_tab.c computes them, and stored as
-- numbers. The precision is not optional: the recorder emits
-- guards on the sizes it saw, and an approximation fails them.
--
-- Otherwise the sizes become applications of the rehash
-- uninterpreted functions. What they are is then unknown, but
-- they are a function of the sizes before the insertion and of
-- the key, so both sides get the same term for the same
-- insertion and only a real difference between the two traces
-- shows up. The one case still worth spelling out is an
-- insertion into a table whose two parts are both empty, because
-- that is what the guard in front of it establishes.
--
-- The values themselves never move: a table is keyed here by the
-- key rather than by a slot, so where a rehash puts an entry is
-- invisible.
local function rehash(ctx, ct, tab_id, key_op, key)
    if ct == nil then
        return ''
    end
    local lua_key = const_key(key_op, ctx)
    local old_asize = ctx.mem_stack:load_index(
        tab_id, ASIZE_ID, op_type.INT
    )
    local old_hmask = ctx.mem_stack:load_index(
        tab_id, HMASK_ID, op_type.INT
    )
    local new_asize = ('(tab_rehash_asize %s %s %s)'):format(
        old_asize, old_hmask, key
    )
    local new_hmask = ('(tab_rehash_hmask %s %s %s)'):format(
        old_asize, old_hmask, key
    )
    -- Whatever size the table was created with is stale now.
    ct.asize, ct.hmask = nil, nil
    local empty_case = ''
    if lua_key ~= nil then
        local zero = arith_utils.const_int_to_smt_bv(0)
        local ea, eh = sizes_after_first(lua_key)
        empty_case = ('(assert (=> (and (= %s %s) (= %s %s))'
            .. '\n    (and (= %s %s) (= %s %s))))\n'):format(
            old_asize, zero, old_hmask, zero,
            new_asize, arith_utils.const_int_to_smt_bv(ea),
            new_hmask, arith_utils.const_int_to_smt_bv(eh)
        )
    end
    return ('%s%s\n%s\n'):format(
        empty_case,
        ctx.mem_stack:store_index(
            tab_id, ASIZE_ID, new_asize, op_type.INT
        ),
        ctx.mem_stack:store_index(
            tab_id, HMASK_ID, new_hmask, op_type.INT
        )
    )
end

impls.IRNodeNEWREFP32 = {}
ir_node.extended(impls.IRNodeNEWREFP32, ir_node.ir_node_base)

function impls.IRNodeNEWREFP32:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local right_op = self:get_right_op()
    local raw_key = ir_node.retrieve_raw_val(right_op, ctx)
    local id = arith_utils.normalize_table_key(raw_key)
    local ssa_ref = self:get_ssa_reference()
    local tab_ssa = left_op:get_ssa()
    if ctx.const_tabs[tab_ssa] == nil then
        ctx.const_tabs[tab_ssa] = {content = {}}
    end
    ctx.const_tabs[ssa_ref] = ctx.const_tabs[tab_ssa]
    if right_op:is_str() then
        ctx.href_keys[ssa_ref] = right_op:get_str()
    end
    local tab_id = ctx.op_stack:load(left_op:get_ssa(), op_type.TAB)
    local p32 = ir_node.make_tab_ref(tab_id, id)
    local out = rehash(
        ctx, ctx.const_tabs[tab_ssa], tab_id, right_op, id
    ) .. ctx.op_stack:store(ssa_ref, op_type.ANY, p32)

    -- Correct NEWREF should hold nil.
    -- Buggy LuaJIT version may omit that guard at *every*
    -- optimisation level, so comparing the opt and unopt traces
    -- can't see it. We emit the guard on the reference (unopt)
    -- side only, as a trace exit: if the optimised trace lacks
    -- an equivalent guard, a NaN key makes the two traces
    -- diverge and the equivalence check returns SAT. Guarded
    -- by `((_ is fp-val) key)` so non-float keys never trigger
    -- it.
    if ctx.is_reference and not right_op:is_str() then
        self:get_flags().irt_guard = true
        local guard = (
            '(or (not ((_ is fp-val) %s)) (not (fp.isNaN (get-fp %s))))'
        ):format(raw_key, raw_key)
        out = out .. '\n' .. ctx.te_stack:store(ssa_ref, guard)
    end
    return out
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
