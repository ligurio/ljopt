--[[
Provides mapping between IR node opcodes and their translators.
]]--

local dev_checks = require('ljopt.dev_checks')
local ljopt_config = require('ljopt.config')
local utils = require('ljopt.utils')
local op_type = require('ljopt.ir.op_type')

local ir_node_ADD = require('ljopt.ir.ADD')
local ir_node_BAND = require('ljopt.ir.BAND')
local ir_node_BROL = require('ljopt.ir.BROL')
local ir_node_CONV = require('ljopt.ir.CONV')
local ir_node_DIV = require('ljopt.ir.DIV')
local ir_node_EQ = require('ljopt.ir.EQ')
local ir_node_FLOAD = require('ljopt.ir.FLOAD')
local ir_node_LE = require('ljopt.ir.LE')
local ir_node_MUL = require('ljopt.ir.MUL')
local ir_node_NEG = require('ljopt.ir.NEG')
local ir_node_NE = require('ljopt.ir.NE')
local ir_node_NOP = require('ljopt.ir.NOP')
local ir_node_SLOAD = require('ljopt.ir.SLOAD')
local ir_node_SUB = require('ljopt.ir.SUB')
local ir_node_ULE = require('ljopt.ir.ULE')

local opcodes_table = {
    -- Constants.
    ['KPRI'] = false,
    ['KINT'] = false,
    ['KGC'] = false,
    ['KPTR'] = false,
    ['KKPTR'] = false,
    ['KNULL'] = false,
    ['KNUM'] = false,
    ['KINT64'] = false,
    ['KSLOT'] = false,
    -- Guarded Assertions.
    ['OP'] = false,
    ['LT'] = require('ljopt.ir.LT'),
    ['GE'] = require('ljopt.ir.GE'),
    ['LE'] = ir_node_LE,
    ['GT'] = require('ljopt.ir.GT'),
    ['UGE'] = require('ljopt.ir.UGE'),
    ['ULE'] = ir_node_ULE,
    ['ULT'] = require('ljopt.ir.ULT'),
    ['UGT'] = require('ljopt.ir.UGT'),
    ['EQ'] = ir_node_EQ,
    ['NE'] = ir_node_NE,
    ['ABC'] = false,
    ['RETF'] = false,
    -- Bit Ops.
    ['BNOT'] = require('ljopt.ir.BNOT'),
    ['BSWAP'] = require('ljopt.ir.BSWAP'),
    ['BAND'] = ir_node_BAND,
    ['BOR'] = require('ljopt.ir.BOR'),
    ['BXOR'] = require('ljopt.ir.BXOR'),
    ['BSHL'] = require('ljopt.ir.BSHL'),
    ['BSHR'] = require('ljopt.ir.BSHR'),
    ['BSAR'] = require('ljopt.ir.BSAR'),
    ['BROL'] = ir_node_BROL,
    ['BROR'] = require('ljopt.ir.BROR'),
    -- Arithmetic Ops.
    -- Not all arithmetic operations have native support in SMT.
    -- Some of them can be easily implemented manually (MAX, MIN)
    -- The others are hard to implement. Track progress here:
    -- https://github.com/ligurio/ljopt/issues/25
    ['ADD'] = ir_node_ADD,
    ['SUB'] = ir_node_SUB,
    ['MUL'] = ir_node_MUL,
    ['DIV'] = ir_node_DIV,
    ['MOD'] = require('ljopt.ir.MOD'),
    ['POW'] = false,
    ['NEG'] = ir_node_NEG,
    ['ABS'] = require('ljopt.ir.ABS'),
    ['ATAN2'] = false,
    ['LDEXP'] = false,
    ['MIN'] = require('ljopt.ir.MIN'),
    ['MAX'] = require('ljopt.ir.MAX'),
    ['FPMATH'] = require('ljopt.ir.FPMATH'),
    ['ADDOV'] = require('ljopt.ir.ADDOV'),
    ['SUBOV'] = require('ljopt.ir.SUBOV'),
    ['MULOV'] = require('ljopt.ir.MULOV'),
    ['FPM_FLOOR'] = false,
    ['FPM_CEIL'] = false,
    ['FPM_TRUNC'] = false,
    ['FPM_SQRT'] = false,
    ['FPM_EXP'] = false,
    ['FPM_EXP2'] = false,
    ['FPM_LOG'] = false,
    ['FPM_LOG2'] = false,
    ['FPM_LOG10'] = false,
    ['FPM_SIN'] = false,
    ['FPM_COS'] = false,
    ['FPM_TAN'] = false,
    -- Memory References.
    ['AREF'] = require('ljopt.ir.AREF'),
    ['HREFK'] = require('ljopt.ir.HREFK'),
    ['HREF'] = require('ljopt.ir.HREF'),
    ['NEWREF'] = require('ljopt.ir.NEWREF'),
    ['UREFO'] = false,
    ['UREFC'] = false,
    ['FREF'] = false,
    ['STRREF'] = false,
    -- Loads and Stores.
    ['ALOAD'] = require('ljopt.ir.ALOAD'),
    ['HLOAD'] = require('ljopt.ir.HLOAD'),
    ['ULOAD'] = false,
    ['FLOAD'] = ir_node_FLOAD,
    ['XLOAD'] = false,
    ['SLOAD'] = ir_node_SLOAD,
    ['VLOAD'] = false,
    ['ASTORE'] = require('ljopt.ir.ASTORE'),
    ['HSTORE'] = require('ljopt.ir.HSTORE'),
    ['USTORE'] = false,
    ['FSTORE'] = require('ljopt.ir.FSTORE'),
    ['XSTORE'] = false,
    -- Allocations.
    ['SNEW'] = false,
    ['XSNEW'] = false,
    ['TNEW'] = require('ljopt.ir.TNEW'),
    ['TDUP'] = false,
    ['CNEW'] = require('ljopt.ir.CNEW'),
    ['CNEWI'] = require('ljopt.ir.CNEWI'),
    -- Strings.
    ['BUFHDR'] = require('ljopt.ir.BUFHDR'),
    ['BUFPUT'] = require('ljopt.ir.BUFPUT'),
    ['BUFSTR'] = require('ljopt.ir.BUFSTR'),
    -- Barriers.
    ['TBAR'] = false,
    ['OBAR'] = false,
    ['XBAR'] = false,
    -- Type Conversions.
    ['CONV'] = ir_node_CONV,
    ['TOBIT'] = false,
    ['TOSTR'] = require('ljopt.ir.TOSTR'),
    ['STRTO'] = require('ljopt.ir.STRTO'),
    -- Calls.
    ['CALLN'] = false,
    ['CALLL'] = false,
    ['CALLS'] = false,
    ['CALLXS'] = false,
    ['CARG'] = false,
    -- Miscellaneous Ops.
    ['SNAP'] = false,
    ['NOP'] = ir_node_NOP,
    ['BASE'] = false,
    ['PVAL'] = false,
    ['GCSTEP'] = false,
    ['HIOP'] = false,
    ['LOOP'] = false,
    ['USE'] = false,
    ['PHI'] = false,
    ['RENAME'] = false,
}

local function get_all_count()
    local count = 0
    for _ in pairs(opcodes_table) do count = count + 1 end
    return count
end

local function get_supported_count()
    local supported_count = 0
    for _, v in pairs(opcodes_table) do
        if v and v.is_dummy_node then
            supported_count = supported_count + 1
        end
    end
    return supported_count
end

local function get_unsupported_count()
    return get_all_count() - get_supported_count()
end

local function get_node(opcode, type)
    local type_table = {
        -- NOP doesn't have a type.
        ['nil'] = '',

        ['fal'] = 'Fal',
        ['tru'] = 'Tru',
        ['lud'] = 'Lud',
        ['str'] = 'Str',
        ['p32'] = 'P32',
        ['thr'] = 'Thr',
        ['pro'] = 'Pro',
        ['fun'] = 'Fun',
        ['p64'] = 'P64',
        ['cdt'] = 'Cdt',
        ['tab'] = 'Tab',
        ['udt'] = 'Udt',
        ['flt'] = 'Flt',
        ['num'] = 'Num',
        ['i8'] = 'I8',
        ['u8'] = 'U8',
        ['i16'] = 'I16',
        ['u16'] = 'U16',
        ['int'] = 'Int',
        ['u32'] = 'U32',
        ['i64'] = 'I64',
        ['u64'] = 'U64',
        ['sfp'] = 'Sfp',
    }
    local node_str = 'IRNode' .. opcode
    assert(not ljopt_config.is_strict_mode() or type_table[type],
        'Unsupported type `' .. type .. '` for ' .. opcode
    )
    assert(not ljopt_config.is_strict_mode() or opcodes_table[opcode],
        'Unsupported operation ' .. opcode
    )
    node_str = node_str .. type_table[type]
    if not opcodes_table[opcode] then
        return nil
    end
    local node = opcodes_table[opcode].instance(node_str, type)
    assert(not ljopt_config.is_strict_mode() or node,
        'Node ' .. node_str .. ' is nil!'
    )
    return node
end

local function instance(ssa_ref, flags, type, opcode, left_op, right_op)
    dev_checks('string', 'table', '?string', 'string', '?table', '?table')
    local node = get_node(opcode, type)
    return node:new(ssa_ref, flags, type, opcode, left_op, right_op)
end

-- Extract the SSA reference number from a raw {type, value} irins
-- operand. Returns the integer SSA ref when the operand is an SSA
-- reference, else nil.
local function raw_ssa_ref(raw_op)
    if raw_op ~= nil and raw_op.type == op_type.SSA then
        return raw_op.value
    end
    return nil
end

-- Let's mark all unimplemented nodes and ignore them and their
-- dependencies.
local function get_nyi_nodes(nodes)
    local nyi_nodes = {}
    local in_loop = false
    for i = 1, table.getn(nodes) do
        local lua_node = nodes[i]
        in_loop = in_loop or lua_node.irop == "LOOP"
        local node = get_node(lua_node.irop, lua_node.irtype)
        if node == nil or in_loop then
            nyi_nodes[i] = true
            local loop_debug_str = in_loop and 'in_loop' or 'no_loop'
            utils.debug_msg(('%d: NYI node %s %s'):format(
                i, 'IRNode' .. lua_node.irop .. lua_node.irtype, loop_debug_str
            ))
        else
            -- Check whether either SSA operand
            -- depends on a NYI node.
            local dep1 = raw_ssa_ref(lua_node.op1)
            local dep2 = raw_ssa_ref(lua_node.op2)
            if (dep1 and nyi_nodes[dep1]) or (dep2 and nyi_nodes[dep2]) then
                nyi_nodes[i] = true
                utils.debug_msg(
                    ('%d: NYI one of the arguments for %s'):format(
                        i, 'IRNode' .. lua_node.irop .. lua_node.irtype
                    )
                )
            else
                -- Convert raw tables to OpType for
                -- is_implemented checks so implementations
                -- can inspect operand kinds cleanly.
                local left_op  = op_type.from_raw(
                    lua_node.op1, lua_node.op1_txt
                )
                local right_op = op_type.from_raw(
                    lua_node.op2, lua_node.op2_txt
                )
                if node.is_implemented(lua_node.flags, lua_node.irtype,
                        lua_node.irop, left_op, right_op) == false then
                    nyi_nodes[i] = true
                    utils.debug_msg(('%d: NYI part of node %s'):format(
                        i, 'IRNode' .. nodes[i].irop .. nodes[i].irtype
                    ))
                end
            end
        end
    end
    return nyi_nodes
end

return {
    instance = instance,
    get_nyi_nodes = get_nyi_nodes,
    get_supported_count = get_supported_count,
    get_unsupported_count = get_unsupported_count,
    get_all_count = get_all_count,
}
