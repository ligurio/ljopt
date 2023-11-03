-- BC to SMT-LIB
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Bytecodes

-- BC ops blacklist.
local bc_ops_bl = {
    -- Comparison ops.
    ["ISLT"] = false,
    ["ISGE"] = false,
    ["ISLE"] = false,
    ["ISGT"] = false,
    ["ISEQV"] = false,
    ["ISNEV"] = false,
    ["ISEQS"] = false,
    ["ISNES"] = false,
    ["ISEQN"] = false,
    ["ISNEN"] = false,
    ["ISEQP"] = false,
    ["ISNEP"] = false,
    -- Unary Test and Copy ops.
    ["ISTC"] = false,
    ["ISFC"] = false,
    ["IST"] = false,
    ["ISF"] = false,
    -- Unary ops.
    ["MOV"] = false,
    ["NOT"] = false,
    ["UNM"] = false,
    ["LEN"] = false,
    -- Binary ops.
    ["ADDVN"] = false,
    ["SUBVN"] = false,
    ["MULVN"] = false,
    ["DIVVN"] = false,
    ["MODVN"] = false,
    ["ADDNV"] = false,
    ["SUBNV"] = false,
    ["MULNV"] = false,
    ["DIVNV"] = false,
    ["MODNV"] = false,
    ["ADDVV"] = false,
    ["SUBVV"] = false,
    ["MULVV"] = false,
    ["DIVVV"] = false,
    ["MODVV"] = false,
    ["POW"] = false,
    ["CAT"] = false,
    -- Constant ops.
    ["KSTR"] = false,
    ["KCDATA"] = false,
    ["KSHORT"] = false,
    ["KNUM"] = false,
    ["KPRI"] = false,
    ["KNIL"] = false,
    -- Upvalue and Function ops.
    ["UGET"] = false,
    ["USETV"] = false,
    ["USETS"] = false,
    ["USETN"] = false,
    ["USETP"] = false,
    ["UCLO"] = false,
    ["FNEW"] = false,
    -- Table ops.
    ["TNEW"] = false,
    ["TDUP"] = false,
    ["GGET"] = false,
    ["GSET"] = false,
    ["TGETV"] = false,
    ["TGETS"] = false,
    ["TGETB"] = false,
    ["TSETV"] = false,
    ["TSETS"] = false,
    ["TSETB"] = false,
    ["TSETM"] = false,
    -- Calls and Vararg Handling.
    ["CALLM"] = false,
    ["CALL"] = false,
    ["CALLMT"] = false,
    ["CALLT"] = false,
    ["ITERC"] = false,
    ["ITERN"] = false,
    ["VARG"] = false,
    ["ISNEXT"] = false,
    -- Returns.
    ["RETM"] = false,
    ["RET"] = false,
    ["RET0"] = false,
    ["RET1"] = false,
    -- Loops and branches.
    ["FORI"] = false,
    ["JFORI"] = false,
    ["FORL"] = false,
    ["IFORL"] = false,
    ["JFORL"] = false,
    ["ITERL"] = false,
    ["IITERL"] = false,
    ["JITERL"] = false,
    ["LOOP"] = false,
    ["ILOOP"] = false,
    ["JLOOP"] = false,
    ["JMP"] = false,
    -- Function headers.
    ["FUNCF"] = false,
    ["IFUNCF"] = false,
    ["JFUNCF"] = false,
    ["FUNCV"] = false,
    ["IFUNCV"] = false,
    ["JFUNCV"] = false,
    ["FUNCC"] = false,
    ["FUNCCW"] = false,
    ["FUNC*"] = false,
}

local function translate()
end

return {
    translate = translate,
}
