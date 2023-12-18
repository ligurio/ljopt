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

return {
    translate = translate,
}
