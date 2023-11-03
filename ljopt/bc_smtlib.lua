-- Translate BC to SMT-LIB.
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Bytecodes
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations#bytecode-optimizations
-- src/lj_parse.c

-- BC ops blacklist.
local bc_ops_bl = {
    -- Comparison ops.
    ["ISLT"] = true,
    ["ISGE"] = true,
    ["ISLE"] = true,
    ["ISGT"] = true,
    ["ISEQV"] = true,
    ["ISNEV"] = true,
    ["ISEQS"] = true,
    ["ISNES"] = true,
    ["ISEQN"] = true,
    ["ISNEN"] = true,
    ["ISEQP"] = true,
    ["ISNEP"] = true,
    -- Unary Test and Copy ops.
    ["ISTC"] = true,
    ["ISFC"] = true,
    ["IST"] = true,
    ["ISF"] = true,
    -- Unary ops.
    ["MOV"] = true,
    ["NOT"] = true,
    ["UNM"] = true,
    ["LEN"] = true,
    -- Binary ops.
    ["ADDVN"] = true,
    ["SUBVN"] = true,
    ["MULVN"] = true,
    ["DIVVN"] = true,
    ["MODVN"] = true,
    ["ADDNV"] = true,
    ["SUBNV"] = true,
    ["MULNV"] = true,
    ["DIVNV"] = true,
    ["MODNV"] = true,
    ["ADDVV"] = true,
    ["SUBVV"] = true,
    ["MULVV"] = true,
    ["DIVVV"] = true,
    ["MODVV"] = true,
    ["POW"] = true,
    ["CAT"] = true,
    -- Constant ops.
    ["KSTR"] = true,
    ["KCDATA"] = true,
    ["KSHORT"] = true,
    ["KNUM"] = true,
    ["KPRI"] = true,
    ["KNIL"] = true,
    -- Upvalue and Function ops.
    ["UGET"] = true,
    ["USETV"] = true,
    ["USETS"] = true,
    ["USETN"] = true,
    ["USETP"] = true,
    ["UCLO"] = true,
    ["FNEW"] = true,
    -- Table ops.
    ["TNEW"] = true,
    ["TDUP"] = true,
    ["GGET"] = true,
    ["GSET"] = true,
    ["TGETV"] = true,
    ["TGETS"] = true,
    ["TGETB"] = true,
    ["TSETV"] = true,
    ["TSETS"] = true,
    ["TSETB"] = true,
    ["TSETM"] = true,
    -- Calls and Vararg Handling.
    ["CALLM"] = true,
    ["CALL"] = true,
    ["CALLMT"] = true,
    ["CALLT"] = true,
    ["ITERC"] = true,
    ["ITERN"] = true,
    ["VARG"] = true,
    ["ISNEXT"] = true,
    -- Returns.
    ["RETM"] = true,
    ["RET"] = true,
    ["RET0"] = true,
    ["RET1"] = true,
    -- Loops and branches.
    ["FORI"] = true,
    ["JFORI"] = true,
    ["FORL"] = true,
    ["IFORL"] = true,
    ["JFORL"] = true,
    ["ITERL"] = true,
    ["IITERL"] = true,
    ["JITERL"] = true,
    ["LOOP"] = true,
    ["ILOOP"] = true,
    ["JLOOP"] = true,
    ["JMP"] = true,
    -- Function headers.
    ["FUNCF"] = true,
    ["IFUNCF"] = true,
    ["JFUNCF"] = true,
    ["FUNCV"] = true,
    ["IFUNCV"] = true,
    ["JFUNCV"] = true,
    ["FUNCC"] = true,
    ["FUNCCW"] = true,
    ["FUNC*"] = true,
}

local function is_supported_bc_op(op)
    return bc_ops_bl[op] == false
end

local function translate(bc)
    for _, op in pairs(bc) do
        is_supported_bc_op()
    end

    return "" -- FIXME
end

return {
    translate = translate,
}
