local function instance(ssa_ref, flags, type, opcode, left_op, right_op)
    local opcode_table = {
        -- Constants.
        "KPRI",   -- TODO: Support.
        "KINT",   -- TODO: Support.
        "KGC",    -- TODO: Support.
        "KPTR",   -- TODO: Support.
        "KKPTR",  -- TODO: Support.
        "KNULL",  -- TODO: Support.
        "KNUM",   -- TODO: Support.
        "KINT64", -- TODO: Support.
        "KSLOT",  -- TODO: Support.
        -- Guarded Assertions.
        "OP",     -- TODO: Support.
        "LT",     -- TODO: Support.
        "GE",     -- TODO: Support.
        ["LE"] = require("ljopt/ir_smtlib/ir_nodes/guarded_assertions/ir_LE"),
        "GT",     -- TODO: Support.
        "ULT",    -- TODO: Support.
        "UGE",    -- TODO: Support.
        "ULE",    -- TODO: Support.
        "UGT",    -- TODO: Support.
        ["EQ"] = require("ljopt/ir_smtlib/ir_nodes/guarded_assertions/ir_EQ"),
        "NE",     -- TODO: Support.
        ["ABC"] = require("ljopt/ir_smtlib/ir_nodes/guarded_assertions/ir_ABC"),
        "RETF",   -- TODO: Support.
        -- Bit Ops.
        "BNOT",   -- TODO: Support.
        "BSWAP",  -- TODO: Support.
        "BAND",   -- TODO: Support.
        "BOR",    -- TODO: Support.
        "BXOR",   -- TODO: Support.
        "BSHL",   -- TODO: Support.
        "BSHR",   -- TODO: Support.
        "BSAR",   -- TODO: Support.
        "BROL",   -- TODO: Support.
        "BROR",   -- TODO: Support.
        -- Arithmetic Ops.
        ["ADD"] = require("ljopt/ir_smtlib/ir_nodes/arithmetic_ops/ir_ADD"),
        ["SUB"] = require("ljopt/ir_smtlib/ir_nodes/arithmetic_ops/ir_SUB"),
        ["MUL"] = require("ljopt/ir_smtlib/ir_nodes/arithmetic_ops/ir_SUB"),
        "DIV",       -- TODO: Support.
        "MOD",       -- TODO: Support.
        "POW",       -- TODO: Support.
        "NEG",       -- TODO: Support.
        "ABS",       -- TODO: Support.
        "ATAN2",     -- TODO: Support.
        "LDEXP",     -- TODO: Support.
        "MIN",       -- TODO: Support.
        "MAX",       -- TODO: Support.
        "FPMATH",    -- TODO: Support.
        "ADDOV",     -- TODO: Support.
        "SUBOV",     -- TODO: Support.
        "MULOV",     -- TODO: Support.
        "FPM_FLOOR", -- TODO: Support.
        "FPM_CEIL",  -- TODO: Support.
        "FPM_TRUNC", -- TODO: Support.
        "FPM_SQRT",  -- TODO: Support.
        "FPM_EXP",   -- TODO: Support.
        "FPM_EXP2",  -- TODO: Support.
        "FPM_LOG",   -- TODO: Support.
        "FPM_LOG2",  -- TODO: Support.
        "FPM_LOG10", -- TODO: Support.
        "FPM_SIN",   -- TODO: Support.
        "FPM_COS",   -- TODO: Support.
        "FPM_TAN",   -- TODO: Support.
        -- Memory References.
        "AREF",      -- TODO: Support.
        "HREFK",     -- TODO: Support.
        "HREF",      -- TODO: Support.
        "NEWREF",    -- TODO: Support.
        "UREFO",     -- TODO: Support.
        "UREFC",     -- TODO: Support.
        "FREF",      -- TODO: Support.
        "STRREF",    -- TODO: Support.
        -- Loads and Stores.
        "ALOAD",     -- TODO: Support.
        "HLOAD",     -- TODO: Support.
        "ULOAD",     -- TODO: Support.
        "FLOAD",     -- TODO: Support.
        "XLOAD",     -- TODO: Support.
        "SLOAD",     -- TODO: Support.
        "VLOAD",     -- TODO: Support.
        "ASTORE",    -- TODO: Support.
        "HSTORE",    -- TODO: Support.
        "USTORE",    -- TODO: Support.
        "FSTORE",    -- TODO: Support.
        "XSTORE",    -- TODO: Support.
        -- Allocations.
        "SNEW",      -- TODO: Support.
        "XSNEW",     -- TODO: Support.
        "TNEW",      -- TODO: Support.
        "TDUP",      -- TODO: Support.
        "CNEW",      -- TODO: Support.
        "CNEWI",     -- TODO: Support.
        -- Barriers.
        "TBAR",      -- TODO: Support.
        "OBAR",      -- TODO: Support.
        "XBAR",      -- TODO: Support.
        -- Type Conversions.
        "CONV",      -- TODO: Support.
        "TOBIT",     -- TODO: Support.
        "TOSTR",     -- TODO: Support.
        "STRTO",     -- TODO: Support.
        -- Calls.
        "CALLN",     -- TODO: Support.
        "CALLL",     -- TODO: Support.
        "CALLS",     -- TODO: Support.
        "CALLXS",    -- TODO: Support.
        "CARG",      -- TODO: Support.
        -- Miscellaneous Ops.
        "NOP",       -- TODO: Support.
        "BASE",      -- TODO: Support.
        "PVAL",      -- TODO: Support.
        "GCSTEP",    -- TODO: Support.
        "HIOP",      -- TODO: Support.
        "LOOP",      -- TODO: Support.
        "USE",       -- TODO: Support.
        "PHI",       -- TODO: Support.
        "RENAME"     -- TODO: Support.
    }
    assert(opcode_table[opcode] ~= nil, "Unsupported operation "..opcode, nil)
    return opcode_table[opcode].instance(ssa_ref, flags, type, left_op, right_op)
end

return {
    instance = instance
}
