-- BC to SMT-LIB
-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Bytecodes

-- Comparison ops

-- ISLT
-- ISGE
-- ISLE
-- ISGT
-- ISEQV
-- ISNEV
-- ISEQS
-- ISNES
-- ISEQN
-- ISNEN
-- ISEQP
-- ISNEP

-- Unary Test and Copy ops

-- ISTC
-- ISFC
-- IST
-- ISF

-- Unary ops

-- MOV
-- NOT
-- UNM
-- LEN

-- Binary ops

-- ADDVN
-- SUBVN
-- MULVN
-- DIVVN
-- MODVN
-- ADDNV
-- SUBNV
-- MULNV
-- DIVNV
-- MODNV
-- ADDVV
-- SUBVV
-- MULVV
-- DIVVV
-- MODVV
-- POW
-- CAT

-- Constant ops

-- KSTR
-- KCDATA
-- KSHORT
-- KNUM
-- KPRI
-- KNIL

-- Upvalue and Function ops

-- UGET
-- USETV
-- USETS
-- USETN
-- USETP
-- UCLO
-- FNEW

-- Table ops

-- TNEW
-- TDUP
-- GGET
-- GSET
-- TGETV
-- TGETS
-- TGETB
-- TSETV
-- TSETS
-- TSETB
-- TSETM

-- Calls and Vararg Handling

-- CALLM
-- CALL
-- CALLMT
-- CALLT
-- ITERC
-- ITERN
-- VARG
-- ISNEXT

-- Returns

-- RETM
-- RET
-- RET0
-- RET1

-- Loops and branches

-- FORI
-- JFORI
-- FORL
-- IFORL
-- JFORL
-- ITERL
-- IITERL
-- JITERL
-- LOOP
-- ILOOP
-- JLOOP
-- JMP

-- Function headers

-- FUNCF
-- IFUNCF
-- JFUNCF
-- FUNCV
-- IFUNCV
-- JFUNCV
-- FUNCC
-- FUNCCW
-- FUNC*

return {
}
