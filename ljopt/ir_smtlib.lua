-- Translate IR to SMT-LIB.
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-SSA-IR
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations#ssa-ir-optimizations

local ir_node = require("ljopt.ir_node")
local smt_context = require("ljopt.smt_context")

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

local vm_stack_prefix = "vm_"
local op_stack_prefix = "op_"
local te_stack_prefix = "te_"
local snap_stack_prefix = "snap_"

local function translate(trace, smt_suffix)
    if (type(trace) ~= "table") then
        error("not a table")
    end

    local smtlib_buf = [[
(set-option :print-success false)
(set-option :produce-models true)
]]

    smt_suffix = smt_suffix or "src"
    -- 0 stage. Create 'smt-context'.
    local ctx_src = smt_context:new("BV", "BV")
    smtlib_buf = smtlib_buf .. ctx_src.vm_stack:init_smt(vm_stack_prefix .. smt_suffix) .. "\n"
    smtlib_buf = smtlib_buf .. ctx_src.op_stack:init_smt(op_stack_prefix .. smt_suffix) .. "\n"
    smtlib_buf = smtlib_buf .. ctx_src.te_stack:init_smt(te_stack_prefix .. smt_suffix) .. "\n"
    smtlib_buf = smtlib_buf .. ctx_src.snap_stack:init_smt(snap_stack_prefix .. smt_suffix) .. "\n"

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
