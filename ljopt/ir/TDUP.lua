-- Table constructor with constant contents: `{10, 20, 30}`.
--
-- TDUP copies a template table the compiler built once, so the
-- contents are known here -- the operand carries the template
-- itself, not just its address. That is what makes the node
-- worth translating: an ALOAD from the copy has to read back the
-- value the constructor put there, and a bounds check against it
-- has to see the size the template was built with.
--
-- The copy is a table this trace allocated, so it gets a local id
-- and is compared only if it escapes, exactly like a TNEW's.
local arith_utils = require('ljopt.ir.arith_utils')
local ir_node = require('ljopt.ir.ir_node_base')
local op_type = require('ljopt.ir.op_type')
local constants = require('ljopt.smt_constants')

local impls = {}

-- A key, as the whole MemCell a store is indexed by. Numbers
-- keep the fp form normalize_table_key() canonicalizes reads to,
-- so a `t[1]` written here is the slot `t[1.0]` reads.
local function key_of(k)
    if type(k) == 'number' then
        return arith_utils.const_num_to_memcell(k)
    elseif type(k) == 'string' then
        return arith_utils.const_str_to_memcell(k)
    end
    return nil
end

-- A value, undecorated: store_index wraps it in the constructor
-- the type asks for. Nested tables are left out -- the copy is
-- shallow, so the entry would have to name the *same* table the
-- template holds, which has no id here.
local function value_of(v)
    if type(v) == 'number' then
        return arith_utils.const_num_to_smt_fp(v), op_type.NUM
    elseif type(v) == 'string' then
        return arith_utils.const_str_to_smt_str(v), op_type.STR
    end
    return nil
end

local function supported(tmpl)
    if type(tmpl) ~= 'table' then
        return false
    end
    for k, v in pairs(tmpl) do
        if key_of(k) == nil or value_of(v) == nil then
            return false
        end
    end
    return true
end

impls.IRNodeTDUPTab = {}
ir_node.extended(impls.IRNodeTDUPTab, ir_node.ir_node_base)

function impls.IRNodeTDUPTab:to_smt_lib(ctx)
    local left_op = self:get_left_op()
    local tmpl = left_op:get_tab()
    local asize, hmask = left_op.asize, left_op.hmask

    local ssa_ref = self:get_ssa_reference()
    local idx, init = ctx.mem_stack:allocate_local(ssa_ref)
    ctx.const_tabs[ssa_ref] = {asize = asize, hmask = hmask, content = {}}

    local out = {
        ctx.te_stack:store(ssa_ref, 'true'),
        init,
        ctx.mem_stack:store_index(
            idx,
            arith_utils.const_str_to_memcell(
                constants.FIELD_TAB_PREFIX .. 'tab.asize'
            ),
            arith_utils.const_int_to_smt_bv(asize), op_type.INT
        ),
        ctx.mem_stack:store_index(
            idx,
            arith_utils.const_str_to_memcell(
                constants.FIELD_TAB_PREFIX .. 'tab.hmask'
            ),
            arith_utils.const_int_to_smt_bv(hmask), op_type.INT
        ),
    }
    for k, v in pairs(tmpl) do
        local val, val_type = value_of(v)
        table.insert(out, ctx.mem_stack:store_index(
            idx, key_of(k), val, val_type
        ))
    end
    table.insert(out, ctx.op_stack:store(ssa_ref, op_type.TAB, tostring(idx)))
    return table.concat(out, '\n')
end

function impls.IRNodeTDUPTab.is_implemented(_flags, _type, _opcode,
                                            left_op, _right_op_val)
    return left_op ~= nil and left_op:is_tab()
        and left_op.asize ~= nil and supported(left_op:get_tab())
end

local function instance(node_str)
    return impls[node_str]
end

return {
    instance = instance
}
