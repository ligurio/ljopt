local opcodes = require("ljopt.irfuzz.opcodes")
local grammar = require("ljopt.irfuzz.grammar")

local T, K, GUARD = grammar.T, grammar.K, grammar.GUARD

local SLOAD_TYPECHECK = 4

local INT_CONSTS = { 0, 1, -1, 2, 3, 7, -7, 8, 0x7fffffff, -0x80000000 }
local NUM_CONSTS = { 0.0, -0.0, 1.0, -1.0, 0.5, 2.0, 3.5, 1/0, -1/0 }
local I64_CONSTS = { 0, 1, -1, 2, 7, 0x7fffffff, -0x80000000 }

local CONST_POOL = {
    [T.INT] = { kind = K.KINT, pool = INT_CONSTS },
    [T.NUM] = { kind = K.KNUM, pool = NUM_CONSTS },
    [T.I64] = { kind = K.KINT64, pool = I64_CONSTS },
}

local INPUT_TYPES = { T.NUM, T.INT }

-- Byte offsets from one FFI base. 0 aliases exactly, 1 and 2
-- partially overlap a wider access, and 4 and 8 are disjoint from
-- a 4-byte access -- the gap aa_xref needs before it can answer
-- ALIAS_NO.
local XMEM_OFFSETS = { 0, 1, 2, 4, 8 }

local function rng_new(seed)
    local state = (seed * 2654435761) % 2 ^ 32
    return function(n)
        state = (state * 1103515245 + 12345) % 2 ^ 32
        local r = math.floor(state / 65536)
        if n then return (r % n) + 1 end
        return r
    end
end

local function gen(seed, opts)
    opts = opts or {}
    local rand = rng_new(seed)
    local ninputs = opts.inputs or 3
    local nbody = opts.insns or 12
    local no_guards = opts.guards == false
    local tables = opts.tables ~= false

    local insns = {}
    local pool = {}
    local hits = {}
    local producer = {}

    local function push(t, idx)
        pool[t] = pool[t] or {}
        table.insert(pool[t], idx)
    end

    -- Refs of type `t` produced by one of `from`, or all of them
    -- when `from` is absent. AREF needs an FLOAD tab.array as its
    -- op1 and a load needs its own AREF/HREF, so an operand spec
    -- names the opcode that has to have produced the ref rather
    -- than just its type.
    local function refs_of(types, from)
        local out = {}
        for _, ty in ipairs(types) do
            for _, idx in ipairs(pool[ty] or {}) do
                if from == nil or from[producer[idx]] then
                    out[#out + 1] = idx
                end
            end
        end
        return out
    end

    local function emit(op, t, ak, av, bk, bv)
        insns[#insns + 1] = { op = opcodes.by_name[op].num, t = t,
                              ak = ak, av = av, bk = bk, bv = bv }
        producer[#insns] = op
        return #insns
    end

    for slot = 1, ninputs do
        local t = INPUT_TYPES[rand(#INPUT_TYPES)]
        push(t, emit("SLOAD", t, K.LIT, slot, K.LIT, SLOAD_TYPECHECK))
    end

    -- A stack slot is never an i64, so the only way one enters a
    -- trace is a CONV. Widening one input up front means the i64
    -- signatures compete for the whole body rather than for
    -- whatever is left after a CONV happens to be picked: without
    -- it the i64 pairs ran 20x rarer than the int ones.
    if #(pool[T.INT] or {}) > 0 then
        local src = pool[T.INT][1]
        push(T.I64, emit("CONV", T.I64, K.REF, src,
            K.LIT, T.I64 * 32 + T.INT + 0x800))
    end

    -- A table also only enters through an SLOAD, and everything
    -- reachable from one (FLOAD tab.array, AREF/HREF, the loads
    -- and stores) is gated behind it.
    if tables then
        local tab = emit("SLOAD", T.TAB, K.LIT, ninputs + 1,
            K.LIT, SLOAD_TYPECHECK)
        push(T.TAB, tab)
        -- The access chain is four links long
        -- (tab -> FLOAD tab.array -> AREF -> load/store), so
        -- materialize it here rather than hoping the random pick
        -- completes it: at a 12-instruction body no ALOAD or HLOAD
        -- was emitted at all, and at 20 only 6 per 100 seeds.
        -- Seeding the refs also makes a store and a load land on
        -- the same one, which is the store-to-load forwarding case
        -- worth checking.
        local arr = emit("FLOAD", T.P32, K.REF, tab,
            K.LIT, grammar.IRFL_TAB_ARRAY)
        push(T.P32, arr)
        -- Two refs per part, on distinct keys. With a single AREF
        -- every access aliases through aa_ahref's `refa == refb`
        -- shortcut and the whole disambiguation path below it --
        -- different constant keys, base+offset arithmetic, key
        -- types -- is unreachable. Fault-injecting that path
        -- against a one-AREF generator reported no miscompile at
        -- all, which is what exposed this.
        local ia = rand(#grammar.ARR_IDXS)
        local ka = rand(#grammar.HASH_KEYS)
        for _, i in ipairs({ ia, (ia % #grammar.ARR_IDXS) + 1 }) do
            push(T.P32, emit("AREF", T.P32, K.REF, arr,
                K.KINT, grammar.ARR_IDXS[i]))
        end
        for _, k in ipairs({ ka, (ka % #grammar.HASH_KEYS) + 1 }) do
            push(T.P32, emit("HREF", T.P32, K.REF, tab,
                K.KINT, grammar.HASH_KEYS[k]))
        end

        -- A function to take upvalue refs from, and a cdata box
        -- whose payload is a base address. Both are SLOAD-only
        -- roots like the table, and both need two refs so the
        -- aliasing questions below them stay reachable.
        local fn = emit("SLOAD", T.FUNC, K.LIT, ninputs + 2,
            K.LIT, SLOAD_TYPECHECK)
        push(T.FUNC, fn)

        -- Two refs of the same UREFx kind on different upvalue
        -- indices, because aa_uref answers a different kind from
        -- its first line and a different index is the case worth
        -- reaching. Each gets a ULOAD so the guard stays live.
        -- Without these a USTORE is only ever satisfiable after
        -- the pick happens to produce a uref first: one store in
        -- 100 seeds, and the aliasing fault below went unreported.
        local kind = ({ "UREFO", "UREFC" })[rand(2)]
        local uv = rand(#grammar.UREF_UVS)
        for _, u in ipairs({ uv, (uv % #grammar.UREF_UVS) + 1 }) do
            local ur = emit(kind, T.P32 + GUARD, K.REF, fn,
                K.LIT, grammar.UREF_UVS[u])
            push(T.P32, ur)
            push(T.NUM, emit("ULOAD", T.NUM + GUARD, K.REF, ur, K.NONE, 0))
        end

        local cd = emit("SLOAD", T.CDATA, K.LIT, ninputs + 3,
            K.LIT, SLOAD_TYPECHECK)
        push(T.CDATA, cd)
        -- Two different offsets, drawn independently. They must
        -- differ, because two identical ADDs are one instruction
        -- after CSE and two before it and the sides then carry a
        -- different number of them; and they must be free to land
        -- far apart, because aa_xref only reaches its
        -- non-overlapping answer when the gap is at least the
        -- access width. Taking adjacent pool entries satisfied the
        -- first and broke the second: every pair was 1 or 2 bytes
        -- apart, so no 4-byte access was ever disjoint and a fault
        -- injected into that branch went unreported.
        local i1 = rand(#XMEM_OFFSETS)
        local i2 = rand(#XMEM_OFFSETS - 1)
        if i2 >= i1 then i2 = i2 + 1 end
        for _, ofs in ipairs({ XMEM_OFFSETS[i1], XMEM_OFFSETS[i2] }) do
            push(T.P64, emit("ADD", T.P64, K.REF, cd, K.KINT, 8 + ofs))
        end
    end

    -- Everything emitted so far is prologue: SLOAD roots and the
    -- hand-built chains below them (the i64 CONV, tab.array, the
    -- AREF/HREF pairs, the upvalue refs, the FFI addresses). Those
    -- are shapes the signature table does not describe -- an
    -- address is `ADD p64 cdata, k`, which is not the ADD any body
    -- rule emits -- so a structural audit checks the body only.
    local nprologue = #insns

    -- Resolve one operand spec at instruction type `t`. Returns
    -- kind, value -- or nil when the current pools cannot satisfy
    -- it, which is what makes an opcode unavailable this round.
    local function resolve(spec, t, allow_const, field, types_override)
        local kind = spec.kind
        if kind == "none" then return K.NONE, 0 end
        if kind == "lit" then return K.LIT, spec.pool[rand(#spec.pool)] end
        if kind == "kint" then return K.KINT, spec.pool[rand(#spec.pool)] end
        if kind == "knum" then return K.KNUM, spec.pool[rand(#spec.pool)] end
        if kind == "field" then return K.LIT, field end

        local types
        if kind == "same" or kind == "same_value" then
            types = { t }
        else
            types = types_override or spec.types
        end
        local wants_const = allow_const
            and (kind == "same_value" or kind == "value")

        local refs = refs_of(types, spec.from)

        if wants_const and (#refs == 0 or rand(5) <= 2) then
            local c = CONST_POOL[types[rand(#types)]]
            if c then return c.kind, c.pool[rand(#c.pool)] end
        end
        if #refs == 0 then return nil end
        return K.REF, refs[rand(#refs)]
    end

    -- CONV couples its two operands: the mode literal names the
    -- source type, so op1 has to be resolved against that mode
    -- rather than independently. Returns the usable variants for
    -- result type `t`.
    local function conv_variants(spec, t)
        local out = {}
        for _, variant in ipairs(spec.conv[t] or {}) do
            for _, src in ipairs(variant[2]) do
                if pool[src] and #pool[src] > 0 then
                    out[#out + 1] = variant
                    break
                end
            end
        end
        return out
    end

    local function satisfiable(spec, t, types_override)
        if spec.kind == "none" or spec.kind == "lit"
            or spec.kind == "kint" or spec.kind == "knum"
            or spec.kind == "field" then
            return true
        end
        if spec.kind == "same_value" or spec.kind == "value" then
            return true
        end
        local types = (spec.kind == "same") and { t }
            or types_override or spec.types
        return #refs_of(types, spec.from) > 0
    end

    -- Candidate (opcode, type) pairs whose operands the current
    -- pools can supply.
    local function candidates()
        local out = {}
        for _, name in ipairs(grammar.covered) do
            local spec = grammar.sig[name]
            local usable = not (spec.guard and no_guards)
            for _, t in ipairs(usable and spec.types or {}) do
                if spec.conv then
                    if #conv_variants(spec, t) > 0 then
                        out[#out + 1] = { name = name, t = t }
                    end
                elseif satisfiable(spec.op1, t,
                        spec.op1_of and spec.op1_of[t])
                    and satisfiable(spec.op2, t) then
                    out[#out + 1] = { name = name, t = t }
                end
            end
        end
        return out
    end

    -- Coverage-guided pick: always choose among the least-emitted
    -- (opcode, type) pairs, so a rare type cannot be crowded out
    -- by the arithmetic ops that accept every type.
    local function pick(cands)
        local best, least = {}, nil
        for _, c in ipairs(cands) do
            local n = hits[c.name .. ":" .. c.t] or 0
            if least == nil or n < least then best, least = { c }, n
            elseif n == least then best[#best + 1] = c end
        end
        return best[rand(#best)]
    end

    for _ = 1, nbody do
        local cands = candidates()
        if #cands == 0 then break end
        local c = pick(cands)
        local spec = grammar.sig[c.name]

        local ak, av, bk, bv
        if spec.conv then
            local vs = conv_variants(spec, c.t)
            local variant = vs[rand(#vs)]
            ak, av = resolve({ kind = "ref", types = variant[2] }, c.t, false)
            bk, bv = K.LIT, variant[1]
        else
            local field = spec.field_of and spec.field_of[c.t]
            local o1t = spec.op1_of and spec.op1_of[c.t]
            ak, av = resolve(spec.op1, c.t, false, field, o1t)
            bk, bv = resolve(spec.op2, c.t, true, field)
        end
        -- A guard comparing a ref with itself is recorder-
        -- impossible in one direction and a tautology in the
        -- other: `x > x` never holds, so the recorder emits the
        -- negated guard instead, and `x <= x` only holds when x is
        -- not a NaN. Either way the two sides disagree about the
        -- exit and the oracle reports a miscompile that no
        -- recorded trace could produce.
        if spec.cmp and ak == K.REF and bk == K.REF and av == bv then
            ak = nil
        end

        if ak ~= nil and bk ~= nil then
            hits[c.name .. ":" .. c.t] = (hits[c.name .. ":" .. c.t] or 0) + 1
            local t = spec.guard and (c.t + GUARD) or c.t
            local idx = emit(c.name, t, ak, av, bk, bv)
            -- Only a compare guard is valueless. ADDOV and its
            -- siblings compute x+y and carry the overflow check,
            -- so their result has to stay usable: an OV op nothing
            -- reads is dead, DCE drops it together with its exit,
            -- and the oracle sees an exit the optimized trace
            -- never takes.
            if not (spec.cmp or spec.novalue or spec.store) then
                push(c.t, idx)
            end

            -- Some refs are guards whose result type the snapshot
            -- cannot carry, so nothing downstream keeps them
            -- alive. Emit the consumer here rather than hoping the
            -- pick supplies one.
            if spec.pair_with then
                local pw = spec.pair_with
                local con = grammar.sig[pw.op]
                local ct = pw.t
                -- The consumer's own op2 still has to be resolved:
                -- a ULOAD takes none, but an FLOAD needs the field
                -- literal its result type selects, and emitting
                -- NONE there reads as field 0, str.len -- a
                -- string's length read off a table.
                local cfield = con.field_of and con.field_of[ct]
                local ck, cv = resolve(con.op2, ct, false, cfield)
                local key = pw.op .. ":" .. ct
                push(ct, emit(pw.op, con.guard and (ct + GUARD) or ct,
                    K.REF, idx, ck, cv))
                hits[key] = (hits[key] or 0) + 1
            end
        end
    end

    return insns, hits, nprologue
end

-- Values worth comparing. Only num and int, matching gen.lua's
-- roots: the final snapshot models Lua stack slots and the
-- equivalence disjunction reads every one of them through
-- get-fp, so an i64 slot -- which no recorder ever writes -- is
-- compared as a float and reads as a miscompile. i64 still
-- appears inside a trace; it just cannot be an output.
local function roots(insns)
    local consumed = {}
    for _, ins in ipairs(insns) do
        if ins.ak == K.REF then consumed[ins.av] = true end
        if ins.bk == K.REF then consumed[ins.bv] = true end
    end
    local sload = opcodes.by_name.SLOAD.num
    local out = {}
    for i, ins in ipairs(insns) do
        -- An OV op's type carries IRT_GUARD, so mask it off: the
        -- value is still a plain int and has to be reachable as an
        -- output, otherwise nothing ever consumes it and DCE takes
        -- the exit with it.
        local t = ins.t % GUARD
        local spec = grammar.sig[opcodes.ops[ins.op + 1].name]
        local valued = spec and not (spec.cmp or spec.novalue or spec.store
            or spec.opaque)
        -- An overflow op is compared whether or not anything reads
        -- it. Being consumed at generation time is not enough:
        -- folding can delete the consumer -- `x ^ x` collapsing to
        -- 0 takes the BSAR that read the ADDOV with it -- and DCE
        -- then drops the ADDOV together with its trace exit, which
        -- reads as the optimized side skipping an exit. Naming it
        -- in the snapshot pins it on both sides.
        local pinned = valued and spec.guard
        if (pinned or not consumed[i]) and ins.op ~= sload
            and valued and (t == T.NUM or t == T.INT) then
            out[#out + 1] = i
        end
    end
    return out
end

return {
    gen = gen,
    roots = roots,
}
