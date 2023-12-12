-- Translate IR to SMT-LIB.
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations#ssa-ir-optimizations

-- IR Types blacklist.
local ir_types_bl = {
    ["nil"] = true,
    ["fal"] = true,
    ["tru"] = true,
    ["lud"] = true,
    ["str"] = true,
    ["p32"] = true,
    ["thr"] = true,
    ["pro"] = true,
    ["fun"] = true,
    ["p64"] = true,
    ["cdt"] = true,
    ["tab"] = true,
    ["udt"] = true,
    ["flt"] = true,
    ["num"] = true,
    ["i8"] = true,
    ["u8"] = true,
    ["i16"] = true,
    ["u16"] = true,
    ["int"] = true,
    ["u32"] = true,
    ["i64"] = true,
    ["u64"] = true,
    ["sfp"] = true,
}

local function is_supported_ir_type(tp)
    return ir_types_bl[tp] == false
end

local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node")

local function construct_nodes(trace)
    local nodes_table = {}
    for i = 1, #trace do
        nodes_table[i] = ir_node.instance(
            trace[i].ssa_ref,
            trace[i].flags,
            trace[i].type,
            trace[i].opcode,
            trace[i].left_op,
            trace[i].right_op
        )
    end
    return nodes_table
end

-- Nodes transformers.
local function identity_transform(nodes)
    return nodes
end

local function loop_unrooling_transform(nodes)
    return nodes -- TODO: Implement.
end

local function function_inlining_transform(nodes)
    return nodes -- TODO: Implement.
end

local all_node_transforms = {
    identity_transform = identity_transform,
    function_inlining_transform = function_inlining_transform,
    loop_unrooling_transform = loop_unrooling_transform
}

local function transform_nodes(nodes)
    for i = 1, #all_node_transforms do
        nodes = all_node_transforms[i](nodes)
    end

    return nodes
end

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ',\n'
      end
      return s .. '} '
   else
      return '"' .. tostring(o) .. '"'
   end
end


local smt_context = require("ljopt/ir_smtlib/smt_context")

local vm_stack_name = "vm_"
local op_stack_name = "op_"
local te_stack_name = "te_"

local function translate(trace, smt_suffix)
    if (type(trace) ~= "table") then
        error("not a table")
    end

    -- print(dump(trace))
 
    local smtlib_buf = [[
(set-option :print-success false)
(set-option :produce-models true)
]]

    smt_suffix = smt_suffix or "src"
    -- 0 stage. Create 'smt-context'.
    local ctx_src = smt_context:new("BV", "BV")
    smtlib_buf = smtlib_buf .. ctx_src.vm_stack:init_smt(vm_stack_name .. smt_suffix) .. "\n"
    smtlib_buf = smtlib_buf .. ctx_src.op_stack:init_smt(op_stack_name .. smt_suffix) .. "\n"
    smtlib_buf = smtlib_buf .. ctx_src.te_stack:init_smt(te_stack_name .. smt_suffix) .. "\n"
    -- print(ctx_src.te_stack:init_smt("snap_" .. smt_suffix))

    -- 1st stage. Constructing list of `ir_nodes` from raw string data.
    local nodes = construct_nodes(trace)

    -- 2nd stage. Transformations (loop unrooling, function inlining, ...).
    nodes = transform_nodes(nodes)

    -- 3rd stage. Converting to SMT-LIB.
    for i = 1, #nodes do
        local parsed_ir = (nodes[i]:get_ssa_reference() or '') .. " "
            .. (nodes[i]:get_flags() or '') .. " "
            .. (nodes[i]:get_type() or '') .. " "
            .. (nodes[i]:get_opcode() or '') .. " "
            .. (nodes[i]:get_left_op() or '') .. " "
            .. (nodes[i]:get_right_op() or '') .. " "

        smtlib_buf = smtlib_buf .. "; " .. parsed_ir .. "\n" .. nodes[i]:to_smt_lib(ctx_src) .. "\n"

    end
    return smtlib_buf
end



-- Arthur's example
local function compare_smt(src_suffix, dst_suffix)
    local check_str = "(assert (= vm_" .. src_suffix .. " " .. "vm_" .. dst_suffix .. "))\n"
                   .. "(assert (distinct (select op_".. src_suffix .." 13) (select op_".. dst_suffix .." 10)))\n"
                   .. "(check-sat)" .. "\n(get-model)"
    return check_str
end

local src_test_TRACE = {
    -- { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#0",                    ["right_op"] = "[ ---- ]" },
    { ["ssa_ref"] = "0001", ["flags"] = nil, ["type"] = "int", ["opcode"] = "SLOAD",  ["left_op"] = "#3",                    ["right_op"] = "CI" },
    { ["ssa_ref"] = "0002", ["flags"] = ">", ["type"] = "num", ["opcode"] = "SLOAD",  ["left_op"] = "#1",                    ["right_op"] = "T" },
    { ["ssa_ref"] = "0003", ["flags"] = nil, ["type"] = "num", ["opcode"] = "CONV",   ["left_op"] = "+0",                    ["right_op"] = "num.int" },
    { ["ssa_ref"] = "0004", ["flags"] = nil, ["type"] = "num", ["opcode"] = "MUL",    ["left_op"] = "-7.0222388080559e+305", ["right_op"] = "0003" },
    { ["ssa_ref"] = "0005", ["flags"] = nil, ["type"] = "num", ["opcode"] = "SUB",    ["left_op"] = "0002",                  ["right_op"] = "0004" },
    -- { ["ssa_ref"] = "0006", ["flags"] = ">", ["type"] = "tab", ["opcode"] = "SLOAD",  ["left_op"] = "#2",                    ["right_op"] = "T" },
    { ["ssa_ref"] = "0007", ["flags"] = nil, ["type"] = "int", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.asize" },
    { ["ssa_ref"] = "0008", ["flags"] = ">", ["type"] = "int", ["opcode"] = "ABC",    ["left_op"] = "0007",                  ["right_op"] = "0001" },
    { ["ssa_ref"] = "0009", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.array" },
    { ["ssa_ref"] = "0010", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "AREF",   ["left_op"] = "0009",                  ["right_op"] = "0001" },
    { ["ssa_ref"] = "0011", ["flags"] = nil, ["type"] = "tab", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.meta" },
    { ["ssa_ref"] = "0012", ["flags"] = ">", ["type"] = "tab", ["opcode"] = "EQ",     ["left_op"] = "0011",                  ["right_op"] = "NULL" },
    { ["ssa_ref"] = "0013", ["flags"] = nil, ["type"] = "num", ["opcode"] = "ASTORE", ["left_op"] = "0010",                  ["right_op"] = "0005" },
    { ["ssa_ref"] = "0014", ["flags"] = "+", ["type"] = "int", ["opcode"] = "ADD",    ["left_op"] = "0001",                  ["right_op"] = "+1" },
    -- { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#1",                    ["right_op"] = "[ ---- ---- ---- ]" },
    { ["ssa_ref"] = "0015", ["flags"] = ">", ["type"] = "int", ["opcode"] = "LE",     ["left_op"] = "0014",                  ["right_op"] = "+100" },
    -- { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#2",                    ["right_op"] = "[ ---- ---- ---- 0014 ---- ---- 0014 ]" },
    { ["ssa_ref"] = "0016", ["flags"] = nil, ["type"] = nil,   ["opcode"] = "LOOP",   ["left_op"] = nil,                     ["right_op"] = nil },
    { ["ssa_ref"] = "0017", ["flags"] = nil, ["type"] = "int", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.asize" },
    { ["ssa_ref"] = "0018", ["flags"] = ">", ["type"] = "int", ["opcode"] = "ABC",    ["left_op"] = "0017",                  ["right_op"] = "0014" },
    { ["ssa_ref"] = "0019", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.array" },
    { ["ssa_ref"] = "0020", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "AREF",   ["left_op"] = "0019",                  ["right_op"] = "0014" },
    { ["ssa_ref"] = "0021", ["flags"] = nil, ["type"] = "tab", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.meta" },
    { ["ssa_ref"] = "0022", ["flags"] = ">", ["type"] = "tab", ["opcode"] = "EQ",     ["left_op"] = "0021",                  ["right_op"] = "NULL" },
    { ["ssa_ref"] = "0023", ["flags"] = nil, ["type"] = "num", ["opcode"] = "ASTORE", ["left_op"] = "0020",                  ["right_op"] = "0005" },
    { ["ssa_ref"] = "0024", ["flags"] = "+", ["type"] = "int", ["opcode"] = "ADD",    ["left_op"] = "0014",                  ["right_op"] = "+1" },
    -- { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#3",                    ["right_op"] = "[ ---- ---- ---- ]" },
    { ["ssa_ref"] = "0025", ["flags"] = ">", ["type"] = "int", ["opcode"] = "LE",     ["left_op"] = "0024",                  ["right_op"] = "+100" },
    { ["ssa_ref"] = "0026", ["flags"] = nil, ["type"] = "int", ["opcode"] = "PHI",    ["left_op"] = "0014",                  ["right_op"] = "0024" }
}

local dst_test_TRACE = {
    -- { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#0",   ["right_op"] = "[ ---- ]" },
    { ["ssa_ref"] = "0001", ["flags"] = nil, ["type"] = "int", ["opcode"] = "SLOAD",  ["left_op"] = "#3",   ["right_op"] = "CI" },
    { ["ssa_ref"] = "0002", ["flags"] = ">", ["type"] = "num", ["opcode"] = "SLOAD",  ["left_op"] = "#1",   ["right_op"] = "T" },
    -- { ["ssa_ref"] = "0003", ["flags"] = ">", ["type"] = "tab",   ["opcode"] = "SLOAD",  ["left_op"] = "#2",   ["right_op"] = "T" },
    { ["ssa_ref"] = "0004", ["flags"] = nil, ["type"] = "int", ["opcode"] = "FLOAD",  ["left_op"] = "0003", ["right_op"] = "tab.asize" },
    { ["ssa_ref"] = "0005", ["flags"] = ">", ["type"] = "int", ["opcode"] = "ABC",    ["left_op"] = "0004", ["right_op"] = "0001" },
    { ["ssa_ref"] = "0006", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "FLOAD",  ["left_op"] = "0003", ["right_op"] = "tab.array" },
    { ["ssa_ref"] = "0007", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "AREF",   ["left_op"] = "0006", ["right_op"] = "0001" },
    { ["ssa_ref"] = "0008", ["flags"] = nil, ["type"] = "tab", ["opcode"] = "FLOAD",  ["left_op"] = "0003", ["right_op"] = "tab.meta" },
    { ["ssa_ref"] = "0009", ["flags"] = ">", ["type"] = "tab", ["opcode"] = "EQ",     ["left_op"] = "0008", ["right_op"] = "NULL" },
    { ["ssa_ref"] = "0010", ["flags"] = nil, ["type"] = "num", ["opcode"] = "ASTORE", ["left_op"] = "0007", ["right_op"] = "0002" },
    { ["ssa_ref"] = "0011", ["flags"] = "+", ["type"] = "int", ["opcode"] = "ADD",    ["left_op"] = "0001", ["right_op"] = "+1" },
    -- { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#1",   ["right_op"] = "[ ---- ---- ---- ]" },
    { ["ssa_ref"] = "0012", ["flags"] = ">", ["type"] = "int", ["opcode"] = "LE",     ["left_op"] = "0011", ["right_op"] = "+100" },
    -- { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#2",   ["right_op"] = "[ ---- ---- ---- 0011 ---- ---- 0011 ]" },
    { ["ssa_ref"] = "0013", ["flags"] = nil, ["type"] = nil,   ["opcode"] = "LOOP",   ["left_op"] = nil,    ["right_op"] = nil },
    { ["ssa_ref"] = "0014", ["flags"] = ">", ["type"] = "int", ["opcode"] = "ABC",    ["left_op"] = "0004", ["right_op"] = "0011" },
    { ["ssa_ref"] = "0015", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "AREF",   ["left_op"] = "0006", ["right_op"] = "0011" },
    { ["ssa_ref"] = "0016", ["flags"] = nil, ["type"] = "num", ["opcode"] = "ASTORE", ["left_op"] = "0015", ["right_op"] = "0002" },
    { ["ssa_ref"] = "0017", ["flags"] = "+", ["type"] = "int", ["opcode"] = "ADD",    ["left_op"] = "0011", ["right_op"] = "+1" },
    -- { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#3",   ["right_op"] = "[ ---- ---- ---- ]" },
    { ["ssa_ref"] = "0018", ["flags"] = ">", ["type"] = "int", ["opcode"] = "LE",     ["left_op"] = "0017", ["right_op"] = "+100" },
    { ["ssa_ref"] = "0019", ["flags"] = nil, ["type"] = "int", ["opcode"] = "PHI",    ["left_op"] = "0011", ["right_op"] = "0017" },
}

-- print(translate(src_test_TRACE, "src"))
-- print(translate(dst_test_TRACE, "dst"))
-- print(compare_smt("src", "dst"))

-- Eugene's example
local test2_traces = {
    ["src"] = {

-- 0001    num SLOAD  #3    I
-- 0002    fun SLOAD  #0    R
-- 0003    tab FLOAD  0002  func.env
-- 0004    int FLOAD  0003  tab.hmask
-- 0005 >  int EQ     0004  +63 
-- 0006    p64 FLOAD  0003  tab.node
-- 0007 >  p64 HREFK  0006  "assert" @20
-- 0008 >  fun HLOAD  0007
-- 0009    tab FLOAD  0002  func.env
-- 0010    int FLOAD  0009  tab.hmask
-- 0011 >  int EQ     0010  +63 
-- 0012    p64 FLOAD  0009  tab.node
-- 0013 >  p64 HREFK  0012  "tonumber" @44
-- 0014 >  fun HLOAD  0013
-- 0015 >  tab SLOAD  #2    T
-- 0016    int FLOAD  0015  tab.hmask
-- 0017 >  int EQ     0016  +15 
-- 0018    p64 FLOAD  0015  tab.node
-- 0019 >  p64 HREFK  0018  "rol" @12
-- 0020 >  fun HLOAD  0019
-- 0021    int FLOAD  0015  tab.hmask
-- 0022 >  int EQ     0021  +15 
-- 0023    p64 FLOAD  0015  tab.node
-- 0024 >  p64 HREFK  0023  "band" @14
-- 0025 >  fun HLOAD  0024
-- 0026 >  fun EQ     0025  bit.band
-- 0027    i64 CONV   0001  i64.num none
-- 0028    u16 FLOAD  127LL  cdata.ctypeid
-- 0029 >  int EQ     0028  +11 
-- 0030    i64 FLOAD  127LL  cdata.int64
-- 0031    i64 BAND   0027  0030
-- 0032 >  cdt CNEWI  +11   0031
-- 0033 >  fun EQ     0020  bit.rol
-- 0034    u16 FLOAD  0032  cdata.ctypeid
-- 0035 >  int EQ     0034  +11 
-- 0036    i64 FLOAD  0032  cdata.int64
-- 0037    i64 BROL   0036  +32 
-- 0038 >  cdt CNEWI  +11   0037
-- 0039 >  fun EQ     0014  tonumber
-- 0040    u16 FLOAD  0038  cdata.ctypeid
-- 0041 >  int EQ     0040  +11 
-- 0042    i64 FLOAD  0038  cdata.int64
-- 0043    num CONV   0042  num.i64
-- 0044    num CONV   +0    num.int
-- 0045 >  num NE     0043  0044
-- 0046 >  fun EQ     0008  assert
-- 0047    num ADD    0001  +1  
-- 0048 >  num LE     0047  +3  

[1] = { ["ssa_ref"] = "0001", ["flags"] = "  ", ["type"] = "num", ["opcode"] = "SLOAD", ["left_op"] = "#3", ["right_op"] = "I", } ,
[2] = { ["ssa_ref"] = "0002", ["flags"] = "  ", ["type"] = "fun", ["opcode"] = "SLOAD", ["left_op"] = "#0", ["right_op"] = "R", } ,
[3] = { ["ssa_ref"] = "0003", ["flags"] = "  ", ["type"] = "tab", ["opcode"] = "FLOAD", ["left_op"] = "0002", ["right_op"] = "func.env", } ,
[4] = { ["ssa_ref"] = "0004", ["flags"] = "  ", ["type"] = "int", ["opcode"] = "FLOAD", ["left_op"] = "0003", ["right_op"] = "tab.hmask", } ,
[5] = { ["ssa_ref"] = "0005", ["flags"] = "> ", ["type"] = "int", ["opcode"] = "EQ", ["left_op"] = "0004", ["right_op"] = "+63", } ,
[6] = { ["ssa_ref"] = "0006", ["flags"] = "  ", ["type"] = "p64", ["opcode"] = "FLOAD", ["left_op"] = "0003", ["right_op"] = "tab.node", } ,
[7] = { ["ssa_ref"] = "0007", ["flags"] = "> ", ["type"] = "p64", ["opcode"] = "HREFK", ["left_op"] = "0006", ["right_op"] = '"assert" @25', } ,
[8] = { ["ssa_ref"] = "0008", ["flags"] = "> ", ["type"] = "fun", ["opcode"] = "HLOAD", ["left_op"] = "0007", } ,
[9] = { ["ssa_ref"] = "0009", ["flags"] = "  ", ["type"] = "tab", ["opcode"] = "FLOAD", ["left_op"] = "0002", ["right_op"] = "func.env", } ,
[10] = { ["ssa_ref"] = "0010", ["flags"] = "  ", ["type"] = "int", ["opcode"] = "FLOAD", ["left_op"] = "0009", ["right_op"] = "tab.hmask", } ,
[11] = { ["ssa_ref"] = "0011", ["flags"] = "> ", ["type"] = "int", ["opcode"] = "EQ", ["left_op"] = "0010", ["right_op"] = "+63", } ,
[12] = { ["ssa_ref"] = "0012", ["flags"] = "  ", ["type"] = "p64", ["opcode"] = "FLOAD", ["left_op"] = "0009", ["right_op"] = "tab.node", } ,
[13] = { ["ssa_ref"] = "0013", ["flags"] = "> ", ["type"] = "p64", ["opcode"] = "HREFK", ["left_op"] = "0012", ["right_op"] = '"tonumber" @49', } ,
[14] = { ["ssa_ref"] = "0014", ["flags"] = "> ", ["type"] = "fun", ["opcode"] = "HLOAD", ["left_op"] = "0013", } ,
[15] = { ["ssa_ref"] = "0015", ["flags"] = "> ", ["type"] = "tab", ["opcode"] = "SLOAD", ["left_op"] = "#2", ["right_op"] = "T", } ,
[16] = { ["ssa_ref"] = "0016", ["flags"] = "  ", ["type"] = "int", ["opcode"] = "FLOAD", ["left_op"] = "0015", ["right_op"] = "tab.hmask", } ,
[17] = { ["ssa_ref"] = "0017", ["flags"] = "> ", ["type"] = "int", ["opcode"] = "EQ", ["left_op"] = "0016", ["right_op"] = "+15", } ,
[18] = { ["ssa_ref"] = "0018", ["flags"] = "  ", ["type"] = "p64", ["opcode"] = "FLOAD", ["left_op"] = "0015", ["right_op"] = "tab.node", } ,
[19] = { ["ssa_ref"] = "0019", ["flags"] = "> ", ["type"] = "p64", ["opcode"] = "HREFK", ["left_op"] = "0018", ["right_op"] = '"rol" @4', } ,
[20] = { ["ssa_ref"] = "0020", ["flags"] = "> ", ["type"] = "fun", ["opcode"] = "HLOAD", ["left_op"] = "0019", } ,
[21] = { ["ssa_ref"] = "0021", ["flags"] = "  ", ["type"] = "int", ["opcode"] = "FLOAD", ["left_op"] = "0015", ["right_op"] = "tab.hmask", } ,
[22] = { ["ssa_ref"] = "0022", ["flags"] = "> ", ["type"] = "int", ["opcode"] = "EQ", ["left_op"] = "0021", ["right_op"] = "+15", } ,
[23] = { ["ssa_ref"] = "0023", ["flags"] = "  ", ["type"] = "p64", ["opcode"] = "FLOAD", ["left_op"] = "0015", ["right_op"] = "tab.node", } ,
[24] = { ["ssa_ref"] = "0024", ["flags"] = "> ", ["type"] = "p64", ["opcode"] = "HREFK", ["left_op"] = "0023", ["right_op"] = '"band" @6', } ,
[25] = { ["ssa_ref"] = "0025", ["flags"] = "> ", ["type"] = "fun", ["opcode"] = "HLOAD", ["left_op"] = "0024", } ,
[26] = { ["ssa_ref"] = "0026", ["flags"] = "> ", ["type"] = "fun", ["opcode"] = "EQ", ["left_op"] = "0025", ["right_op"] = "bit.band", } ,
[27] = { ["ssa_ref"] = "0027", ["flags"] = "  ", ["type"] = "i64", ["opcode"] = "CONV", ["left_op"] = "0001", ["right_op"] = "i64.num", } ,
[28] = { ["ssa_ref"] = "0028", ["flags"] = "  ", ["type"] = "u16", ["opcode"] = "FLOAD", ["left_op"] = "127LL", ["right_op"] = "cdata.ctypeid", } ,
[29] = { ["ssa_ref"] = "0029", ["flags"] = "> ", ["type"] = "int", ["opcode"] = "EQ", ["left_op"] = "0028", ["right_op"] = "+11", } ,
[30] = { ["ssa_ref"] = "0030", ["flags"] = "  ", ["type"] = "i64", ["opcode"] = "FLOAD", ["left_op"] = "127LL", ["right_op"] = "cdata.int64", } ,
[31] = { ["ssa_ref"] = "0031", ["flags"] = "  ", ["type"] = "i64", ["opcode"] = "BAND", ["left_op"] = "0027", ["right_op"] = "0030", } ,
[32] = { ["ssa_ref"] = "0032", ["flags"] = "> ", ["type"] = "cdt", ["opcode"] = "CNEWI", ["left_op"] = "+11", ["right_op"] = "0031", } ,
[33] = { ["ssa_ref"] = "0033", ["flags"] = "> ", ["type"] = "fun", ["opcode"] = "EQ", ["left_op"] = "0020", ["right_op"] = "bit.rol", } ,
[34] = { ["ssa_ref"] = "0034", ["flags"] = "  ", ["type"] = "u16", ["opcode"] = "FLOAD", ["left_op"] = "0032", ["right_op"] = "cdata.ctypeid", } ,
[35] = { ["ssa_ref"] = "0035", ["flags"] = "> ", ["type"] = "int", ["opcode"] = "EQ", ["left_op"] = "0034", ["right_op"] = "+11", } ,
[36] = { ["ssa_ref"] = "0036", ["flags"] = "  ", ["type"] = "i64", ["opcode"] = "FLOAD", ["left_op"] = "0032", ["right_op"] = "cdata.int64", } ,
[37] = { ["ssa_ref"] = "0037", ["flags"] = "  ", ["type"] = "i64", ["opcode"] = "BROL", ["left_op"] = "0036", ["right_op"] = "+32", } ,
[38] = { ["ssa_ref"] = "0038", ["flags"] = "> ", ["type"] = "cdt", ["opcode"] = "CNEWI", ["left_op"] = "+11", ["right_op"] = "0037", } ,
[39] = { ["ssa_ref"] = "0039", ["flags"] = "> ", ["type"] = "fun", ["opcode"] = "EQ", ["left_op"] = "0014", ["right_op"] = "tonumber", } ,
[40] = { ["ssa_ref"] = "0040", ["flags"] = "  ", ["type"] = "u16", ["opcode"] = "FLOAD", ["left_op"] = "0038", ["right_op"] = "cdata.ctypeid", } ,
[41] = { ["ssa_ref"] = "0041", ["flags"] = "> ", ["type"] = "int", ["opcode"] = "EQ", ["left_op"] = "0040", ["right_op"] = "+11", } ,
[42] = { ["ssa_ref"] = "0042", ["flags"] = "  ", ["type"] = "i64", ["opcode"] = "FLOAD", ["left_op"] = "0038", ["right_op"] = "cdata.int64", } ,
[43] = { ["ssa_ref"] = "0043", ["flags"] = "  ", ["type"] = "num", ["opcode"] = "CONV", ["left_op"] = "0042", ["right_op"] = "num.i64", } ,
[44] = { ["ssa_ref"] = "0044", ["flags"] = "  ", ["type"] = "num", ["opcode"] = "CONV", ["left_op"] = "+0", ["right_op"] = "num.int", } ,
[45] = { ["ssa_ref"] = "0045", ["flags"] = "> ", ["type"] = "num", ["opcode"] = "NE", ["left_op"] = "0043", ["right_op"] = "0044", } ,
[46] = { ["ssa_ref"] = "0046", ["flags"] = "> ", ["type"] = "fun", ["opcode"] = "EQ", ["left_op"] = "0008", ["right_op"] = "assert", } ,
[47] = { ["ssa_ref"] = "0047", ["flags"] = "  ", ["type"] = "num", ["opcode"] = "ADD", ["left_op"] = "0001", ["right_op"] = "+1", } ,
[48] = { ["ssa_ref"] = "0048", ["flags"] = "> ", ["type"] = "num", ["opcode"] = "LE", ["left_op"] = "0047", ["right_op"] = "+3", } ,
},
    ["tgt"] = {

    },
}

-- print(translate(test2_traces, "src"))

return {
    translate = translate,
}
