local ir_node_LE = require("ljopt.LE")
local ir_node_ULE = require("ljopt.ULE")
local ir_node_EQ = require("ljopt.EQ")
local ir_node_NE = require("ljopt.NE")
local ir_node_ABC = require("ljopt.ABC")
local ir_node_BAND = require("ljopt.BAND")
local ir_node_BROL = require("ljopt.BROL")
local ir_node_ADD = require("ljopt.ADD")
local ir_node_SUB = require("ljopt.SUB")
local ir_node_MUL = require("ljopt.MUL")
local ir_node_AREF = require("ljopt.AREF")
local ir_node_HREFK = require("ljopt.HREFK")
local ir_node_NEWREF = require("ljopt.NEWREF")
local ir_node_UREFC = require("ljopt.UREFC")
local ir_node_HLOAD = require("ljopt.HLOAD")
local ir_node_FLOAD = require("ljopt.FLOAD")
local ir_node_SLOAD = require("ljopt.SLOAD")
local ir_node_ASTORE = require("ljopt.ASTORE")
local ir_node_HSTORE = require("ljopt.HSTORE")
local ir_node_CNEWI = require("ljopt.CNEWI")
local ir_node_CONV = require("ljopt.CONV")
local ir_node_SNAP = require("ljopt.SNAP")
local ir_node_NOP = require("ljopt.NOP")
local ir_node_LOOP = require("ljopt.LOOP")
local ir_node_PHI = require("ljopt.PHI")

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
        ["LE"] = ir_node_LE,
        "GT",     -- TODO: Support.
        "ULT",    -- TODO: Support.
        "UGE",    -- TODO: Support.
        ["ULE"] = ir_node_ULE,
        "UGT",    -- TODO: Support.
        ["EQ"] = ir_node_EQ,
        ["NE"] = ir_node_NE,
        ["ABC"] = ir_node_ABC,
        "RETF",  -- TODO: Support.
        -- Bit Ops.
        "BNOT",  -- TODO: Support.
        "BSWAP", -- TODO: Support.
        ["BAND"] = ir_node_BAND,
        "BOR",   -- TODO: Support.
        "BXOR",  -- TODO: Support.
        "BSHL",  -- TODO: Support.
        "BSHR",  -- TODO: Support.
        "BSAR",  -- TODO: Support.
        ["BROL"] = ir_node_BROL,
        "BROR",  -- TODO: Support.
        -- Arithmetic Ops.
        ["ADD"] = ir_node_ADD,
        ["SUB"] = ir_node_SUB,
        ["MUL"] = ir_node_MUL,
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
        ["AREF"] = ir_node_AREF,
        ["HREFK"] = ir_node_HREFK,
        "HREF",   -- TODO: Support.
        ["NEWREF"] = ir_node_NEWREF,
        "UREFO",  -- TODO: Support.
        ["UREFC"] = ir_node_UREFC,
        "FREF",   -- TODO: Support.
        "STRREF", -- TODO: Support.
        -- Loads and Stores.
        "ALOAD",  -- TODO: Support.
        ["HLOAD"] = ir_node_HLOAD,
        "ULOAD",  -- TODO: Support.
        ["FLOAD"] = ir_node_FLOAD,
        "XLOAD",  -- TODO: Support.
        ["SLOAD"] = ir_node_SLOAD,
        "VLOAD",  -- TODO: Support.
        ["ASTORE"] = ir_node_ASTORE,
        ["HSTORE"] = ir_node_HSTORE,
        "USTORE", -- TODO: Support.
        "FSTORE", -- TODO: Support.
        "XSTORE", -- TODO: Support.
        -- Allocations.
        "SNEW",   -- TODO: Support.
        "XSNEW",  -- TODO: Support.
        "TNEW",   -- TODO: Support.
        "TDUP",   -- TODO: Support.
        "CNEW",   -- TODO: Support.
        ["CNEWI"] = ir_node_CNEWI,
        -- Barriers.
        "TBAR", -- TODO: Support.
        "OBAR", -- TODO: Support.
        "XBAR", -- TODO: Support.
        -- Type Conversions.
        ["CONV"] = ir_node_CONV,
        "TOBIT",  -- TODO: Support.
        "TOSTR",  -- TODO: Support.
        "STRTO",  -- TODO: Support.
        -- Calls.
        "CALLN",  -- TODO: Support.
        "CALLL",  -- TODO: Support.
        "CALLS",  -- TODO: Support.
        "CALLXS", -- TODO: Support.
        "CARG",   -- TODO: Support.
        -- Miscellaneous Ops.
        ["SNAP"] = ir_node_SNAP,
        ["NOP"] = ir_node_NOP,
        "BASE",   -- TODO: Support.
        "PVAL",   -- TODO: Support.
        "GCSTEP", -- TODO: Support.
        "HIOP",   -- TODO: Support.
        ["LOOP"] = ir_node_LOOP,
        "USE",    -- TODO: Support.
        ["PHI"] = ir_node_PHI,
        "RENAME", -- TODO: Support.
    }
    assert(opcode_table[opcode] ~= nil, "Unsupported operation " .. opcode, nil)
    return opcode_table[opcode].instance(ssa_ref, flags, type, left_op, right_op)
end

return {
    instance = instance
}
