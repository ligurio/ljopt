local ir_node = require("ljopt/ir_smtlib/ir_nodes/ir_node_base")

ir_node_EQ_base = {}
extended(ir_node_EQ_base, ir_node.ir_node_base)

local impls = {}

impls.ir_node_EQ_num = {}
extended(impls.ir_node_EQ_num, ir_node_EQ_base)

function impls.ir_node_EQ_num:to_smt_lib ()
    --TODO: Implement
    return ''
end

impls.ir_node_EQ_flt = {}
extended(impls.ir_node_EQ_flt, ir_node_EQ_base)

impls.ir_node_EQ_i8 = {}
extended(impls.ir_node_EQ_i8, ir_node_EQ_base)

impls.ir_node_EQ_u8 = {}
extended(impls.ir_node_EQ_u8, ir_node_EQ_base)

impls.ir_node_EQ_i16 = {}
extended(impls.ir_node_EQ_i16, ir_node_EQ_base)

impls.ir_node_EQ_u16 = {}
extended(impls.ir_node_EQ_u16, ir_node_EQ_base)

impls.ir_node_EQ_int = {}
extended(impls.ir_node_EQ_int, ir_node_EQ_base)

function impls.ir_node_EQ_int:to_smt_lib ()
    --TODO: Implement
end

impls.ir_node_EQ_u32 = {}
extended(impls.ir_node_EQ_u32, ir_node_EQ_base)

impls.ir_node_EQ_i64 = {}
extended(impls.ir_node_EQ_i64, ir_node_EQ_base)

impls.ir_node_EQ_u64 = {}
extended(impls.ir_node_EQ_u64, ir_node_EQ_base)

impls.ir_node_EQ_sfp = {}
extended(impls.ir_node_EQ_sfp, ir_node_EQ_base)


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
    assert(type_table[type] ~= nil, "Unsupported type for EQ operation", nil)
    return impls["ir_node_EQ_"..type]:new(ssa_ref, flags, type, "EQ", left_op, right_op)
end


return{
    instance = instance
}   