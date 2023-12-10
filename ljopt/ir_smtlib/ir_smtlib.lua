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

local function translate(trace)
    if (type(trace) ~= "table") then
        error("not a table")
    end    
    print(dump(trace))
    local smtlib_buf = [[
(set-option :print-success false)
(set-option :produce-models true)
]]
local smt_context = require("ljopt/ir_smtlib/smt_context")
    -- 0 stage. Create 'smt-context'.
    local ctx_src = smt_context:new("BV", "BV")
    print(ctx_src.vm_stack:init_smt("vm_src"))
    print(ctx_src.op_stack:init_smt("op_src"))
    print(ctx_src.te_stack:init_smt("te_src"))

    -- 1st stage. Constructing list of `ir_nodes` from raw string data.
    local nodes = construct_nodes(trace)

    -- 2nd stage. Transformations (loop unrooling, function inlining, ...).
    nodes = transform_nodes(nodes)

    -- TODO: Create 'smt-context', and pass it to `:to_smt_lib()`

    -- 3rd stage. Converting to SMT-LIB.
    local smt_lib_format = ''
    for i = 1, #nodes do
        local parsed_ir = (nodes[i]:get_ssa_reference() or '').." "
        ..(nodes[i]:get_flags() or '').." "
        ..(nodes[i]:get_type() or '').." "
        ..(nodes[i]:get_opcode() or '').." "
        ..(nodes[i]:get_left_op() or '').." "
        ..(nodes[i]:get_right_op() or '').." "
        print("; "..parsed_ir)

        print(nodes[i]:to_smt_lib(ctx_src))
        print("\n")
    end

    smt_lib_format = smt_lib_format.."(check-sat)".."\n(get-model)"
    return smt_lib_format
end


--- Some IR dump for testing
--[[
    ---- TRACE 1 IR
....        SNAP   #0   [ ---- ]
0001    int SLOAD  #3    CI
0002 >  num SLOAD  #1    T
0003    num CONV   +0    num.int
0004    num MUL    -7.0222388080559e+305  0003
0005    num SUB    0002  0004
0006 >  tab SLOAD  #2    T
0007    int FLOAD  0006  tab.asize
0008 >  int ABC    0007  0001
0009    p32 FLOAD  0006  tab.array
0010    p32 AREF   0009  0001
0011    tab FLOAD  0006  tab.meta
0012 >  tab EQ     0011  NULL
0013    num ASTORE 0010  0005
0014  + int ADD    0001  +1
....        SNAP   #1   [ ---- ---- ---- ]
0015 >  int LE     0014  +100
....        SNAP   #2   [ ---- ---- ---- 0014 ---- ---- 0014 ]
0016 ------ LOOP ------------
0017    int FLOAD  0006  tab.asize
0018 >  int ABC    0017  0014
0019    p32 FLOAD  0006  tab.array
0020    p32 AREF   0019  0014
0021    tab FLOAD  0006  tab.meta
0022 >  tab EQ     0021  NULL
0023    num ASTORE 0020  0005
0024  + int ADD    0014  +1
....        SNAP   #3   [ ---- ---- ---- ]
0025 >  int LE     0024  +100
0026    int PHI    0014  0024
---- TRACE 1 stop -> loop
]]

local test_TRACE = {
    { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#0",                    ["right_op"] = "[ ---- ]" },
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
    { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#1",                    ["right_op"] = "[ ---- ---- ---- ]" },
    { ["ssa_ref"] = "0015", ["flags"] = ">", ["type"] = "int", ["opcode"] = "LE",     ["left_op"] = "0014",                  ["right_op"] = "+100" },
    { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#2",                    ["right_op"] = "[ ---- ---- ---- 0014 ---- ---- 0014 ]" },
    { ["ssa_ref"] = "0016", ["flags"] = nil, ["type"] = nil,   ["opcode"] = "LOOP",   ["left_op"] = nil,                     ["right_op"] = nil },
    { ["ssa_ref"] = "0017", ["flags"] = nil, ["type"] = "int", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.asize" },
    { ["ssa_ref"] = "0018", ["flags"] = ">", ["type"] = "int", ["opcode"] = "ABC",    ["left_op"] = "0017",                  ["right_op"] = "0014" },
    { ["ssa_ref"] = "0019", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.array" },
    { ["ssa_ref"] = "0020", ["flags"] = nil, ["type"] = "p32", ["opcode"] = "AREF",   ["left_op"] = "0019",                  ["right_op"] = "0014" },
    { ["ssa_ref"] = "0021", ["flags"] = nil, ["type"] = "tab", ["opcode"] = "FLOAD",  ["left_op"] = "0006",                  ["right_op"] = "tab.meta" },
    { ["ssa_ref"] = "0022", ["flags"] = ">", ["type"] = "tab", ["opcode"] = "EQ",     ["left_op"] = "0021",                  ["right_op"] = "NULL" },
    { ["ssa_ref"] = "0023", ["flags"] = nil, ["type"] = "num", ["opcode"] = "ASTORE", ["left_op"] = "0020",                  ["right_op"] = "0005" },
    { ["ssa_ref"] = "0024", ["flags"] = "+", ["type"] = "int", ["opcode"] = "ADD",    ["left_op"] = "0014",                  ["right_op"] = "+1" },
    { ["ssa_ref"] = nil,    ["flags"] = nil, ["type"] = nil,   ["opcode"] = "SNAP",   ["left_op"] = "#3",                    ["right_op"] = "[ ---- ---- ---- ]" },
    { ["ssa_ref"] = "0025", ["flags"] = ">", ["type"] = "int", ["opcode"] = "LE",     ["left_op"] = "0024",                  ["right_op"] = "+100" },
    { ["ssa_ref"] = "0026", ["flags"] = nil, ["type"] = "int", ["opcode"] = "PHI",    ["left_op"] = "0014",                  ["right_op"] = "0024" }
}
print(translate(test_TRACE))

return {
    translate = translate,
}
