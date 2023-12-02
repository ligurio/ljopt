local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_MUL_base = {}
extended(ir_node_MUL_base, ir_node.ir_node_base)

local impls = {}

impls.ir_node_MUL_num = {}
extended(impls.ir_node_MUL_num, ir_node_MUL_base)

function impls.ir_node_MUL_num:to_smt_lib ()
    --TODO: Implement
    return ''
end

impls.ir_node_MUL_flt = {}
extended(impls.ir_node_MUL_flt, ir_node_MUL_base)

impls.ir_node_MUL_i8 = {}
extended(impls.ir_node_MUL_i8, ir_node_MUL_base)

impls.ir_node_MUL_u8 = {}
extended(impls.ir_node_MUL_u8, ir_node_MUL_base)

impls.ir_node_MUL_i16 = {}
extended(impls.ir_node_MUL_i16, ir_node_MUL_base)

impls.ir_node_MUL_u16 = {}
extended(impls.ir_node_MUL_u16, ir_node_MUL_base)

impls.ir_node_MUL_int = {}
extended(impls.ir_node_MUL_int, ir_node_MUL_base)

function impls.ir_node_MUL_int:to_smt_lib ()
    --TODO: Implement
    return ''
end

impls.ir_node_MUL_u32 = {}
extended(impls.ir_node_MUL_u32, ir_node_MUL_base)

impls.ir_node_MUL_i64 = {}
extended(impls.ir_node_MUL_i64, ir_node_MUL_base)

impls.ir_node_MUL_u64 = {}
extended(impls.ir_node_MUL_u64, ir_node_MUL_base)

impls.ir_node_MUL_sfp = {}
extended(impls.ir_node_MUL_sfp, ir_node_MUL_base)


function instance(ssa_ref, flags, type, left_op, right_op)
    local type_table = {
        ["num"] = {},
        ["i8"] = {},
        ["u8"] = {},
        ["i16"] = {},
        ["u16"] = {},
        ["int"] = {},
        ["u32"] = {},
        ["i64"] = {},
        ["u64"] = {},
        ["sfp"] = {}
    }
    assert(type_table[type] ~= nil, "Unsupported type for MUL operation", nil)
    return impls["ir_node_MUL_"..type]:new(ssa_ref, flags, type, "MUL", left_op, right_op)
end

return{
    instance = instance
}