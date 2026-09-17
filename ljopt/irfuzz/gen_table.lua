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

    local insns = {}
    local pool = {}
    local hits = {}

    local function push(t, idx)
        pool[t] = pool[t] or {}
        table.insert(pool[t], idx)
    end

    local function emit(op, t, ak, av, bk, bv)
        insns[#insns + 1] = { op = opcodes.by_name[op].num, t = t,
                              ak = ak, av = av, bk = bk, bv = bv }
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

    -- Resolve one operand spec at instruction type `t`. Returns
    -- kind, value -- or nil when the current pools cannot satisfy
    -- it, which is what makes an opcode unavailable this round.
    local function resolve(spec, t, allow_const)
        local kind = spec.kind
        if kind == "none" then return K.NONE, 0 end
        if kind == "lit" then return K.LIT, spec.pool[rand(#spec.pool)] end
        if kind == "kint" then return K.KINT, spec.pool[rand(#spec.pool)] end
        if kind == "knum" then return K.KNUM, spec.pool[rand(#spec.pool)] end

        local types
        if kind == "same" or kind == "same_value" then
            types = { t }
        else
            types = spec.types
        end
        local wants_const = allow_const
            and (kind == "same_value" or kind == "value")

        local refs = {}
        for _, ty in ipairs(types) do
            for _, idx in ipairs(pool[ty] or {}) do refs[#refs + 1] = idx end
        end

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

    local function satisfiable(spec, t)
        if spec.kind == "none" or spec.kind == "lit"
            or spec.kind == "kint" or spec.kind == "knum" then
            return true
        end
        if spec.kind == "same_value" or spec.kind == "value" then
            return true
        end
        local types = (spec.kind == "same") and { t } or spec.types
        for _, ty in ipairs(types) do
            if pool[ty] and #pool[ty] > 0 then return true end
        end
        return false
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
                elseif satisfiable(spec.op1, t)
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
            ak, av = resolve(spec.op1, c.t, false)
            bk, bv = resolve(spec.op2, c.t, true)
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
            if not spec.cmp then push(c.t, idx) end
        end
    end

    return insns, hits
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
        if not consumed[i] and ins.op ~= sload
            and not (spec and spec.cmp)
            and (t == T.NUM or t == T.INT) then
            out[#out + 1] = i
        end
    end
    return out
end

return {
    gen = gen,
    roots = roots,
}
