package = 'ljopt'
version = 'scm-1'
source = {
    url = 'git+https://github.com/ligurio/ljopt',
    branch = 'devel',
}

description = {
    summary = 'Translate LuaJIT IR to SMT-LIB',
    detailed = [[
ljopt is a bounded translation validation tool for the LuaJIT
intermediate representation (IR). It limits resource consumption by, for
example, unrolling loops up to some bound, which means there are circumstances
in which it misses bugs. ljopt is designed to avoid false alarms, is fully
automatic through the use of an SMT solver, and requires no changes to LuaJIT.
    ]],
    homepage = 'https://github.com/ligurio/ljopt',
    maintainer = 'Sergey Bronnikov <estetus@gmail.com>',
    license = 'MIT',
}

external_dependencies = {
    LUAJIT = {
        header = 'luajit-2.1/luajit.h',
    },
}

build = {
    type = 'builtin',
    modules = {
        ljopt = 'ljopt/init.lua',
        ['ljopt.config'] = 'ljopt/config.lua',
        ['ljopt.dev_checks'] = 'ljopt/dev_checks.lua',
        ['ljopt.ir.SNAP'] = 'ljopt/ir/SNAP.lua',
        ['ljopt.ir_dump'] = 'ljopt/ir_dump.lua',
        ['ljopt.ir_dump_utils'] = 'ljopt/ir_dump_utils.lua',
        ['ljopt.ir_passes'] = 'ljopt/ir_passes.lua',
        ['ljopt.ir_smtlib'] = 'ljopt/ir_smtlib.lua',
        ['ljopt.main'] = 'ljopt/main.lua',
        ['ljopt.runtime'] = 'ljopt/runtime.lua',
        ['ljopt.smtlib2'] = 'ljopt/smtlib2.lua',
        ['ljopt.smtlib2_cvc5'] = 'ljopt/smtlib2_cvc5.lua',
        ['ljopt.smtlib2_z3'] = 'ljopt/smtlib2_z3.lua',
        ['ljopt.smt_constants'] = 'ljopt/smt_constants.lua',
        ['ljopt.utils'] = 'ljopt/utils.lua',

        ['ljopt.ir.arith_utils'] = 'ljopt/ir/arith_utils.lua',
        ['ljopt.ir.ir_node_base'] = 'ljopt/ir/ir_node_base.lua',
        ['ljopt.ir.ir_node_dummy'] = 'ljopt/ir/ir_node_dummy.lua',
        ['ljopt.ir.ir_nodes'] = 'ljopt/ir/ir_nodes.lua',
        ['ljopt.ir.op_type'] = 'ljopt/ir/op_type.lua',
        ['ljopt.ir.smt_context'] = 'ljopt/ir/smt_context.lua',

        ['ljopt.ir.BinOp'] = 'ljopt/ir/BinOp.lua',
        ['ljopt.ir.UnOp'] = 'ljopt/ir/UnOp.lua',

        ['ljopt.ir.ABS'] = 'ljopt/ir/ABS.lua',
        ['ljopt.ir.ADD'] = 'ljopt/ir/ADD.lua',
        ['ljopt.ir.ADDOV'] = 'ljopt/ir/ADDOV.lua',
        ['ljopt.ir.DIV'] = 'ljopt/ir/DIV.lua',
        ['ljopt.ir.FPMATH'] = 'ljopt/ir/FPMATH.lua',
        ['ljopt.ir.LDEXP'] = 'ljopt/ir/LDEXP.lua',
        ['ljopt.ir.MOD'] = 'ljopt/ir/MOD.lua',
        ['ljopt.ir.MUL'] = 'ljopt/ir/MUL.lua',
        ['ljopt.ir.MULOV'] = 'ljopt/ir/MULOV.lua',
        ['ljopt.ir.POW'] = 'ljopt/ir/POW.lua',
        ['ljopt.ir.SUB'] = 'ljopt/ir/SUB.lua',
        ['ljopt.ir.SUBOV'] = 'ljopt/ir/SUBOV.lua',

        ['ljopt.ir.BAND'] = 'ljopt/ir/BAND.lua',
        ['ljopt.ir.BNOT'] = 'ljopt/ir/BNOT.lua',
        ['ljopt.ir.BOR'] = 'ljopt/ir/BOR.lua',
        ['ljopt.ir.BROL'] = 'ljopt/ir/BROL.lua',
        ['ljopt.ir.BROR'] = 'ljopt/ir/BROR.lua',
        ['ljopt.ir.BSAR'] = 'ljopt/ir/BSAR.lua',
        ['ljopt.ir.BSHL'] = 'ljopt/ir/BSHL.lua',
        ['ljopt.ir.BSHR'] = 'ljopt/ir/BSHR.lua',
        ['ljopt.ir.BSWAP'] = 'ljopt/ir/BSWAP.lua',
        ['ljopt.ir.BXOR'] = 'ljopt/ir/BXOR.lua',

        ['ljopt.ir.EQ'] = 'ljopt/ir/EQ.lua',
        ['ljopt.ir.GE'] = 'ljopt/ir/GE.lua',
        ['ljopt.ir.GT'] = 'ljopt/ir/GT.lua',
        ['ljopt.ir.LE'] = 'ljopt/ir/LE.lua',
        ['ljopt.ir.LT'] = 'ljopt/ir/LT.lua',
        ['ljopt.ir.MAX'] = 'ljopt/ir/MAX.lua',
        ['ljopt.ir.MIN'] = 'ljopt/ir/MIN.lua',
        ['ljopt.ir.NEG'] = 'ljopt/ir/NEG.lua',
        ['ljopt.ir.NE'] = 'ljopt/ir/NE.lua',
        ['ljopt.ir.UGE'] = 'ljopt/ir/UGE.lua',
        ['ljopt.ir.UGT'] = 'ljopt/ir/UGT.lua',
        ['ljopt.ir.ULE'] = 'ljopt/ir/ULE.lua',
        ['ljopt.ir.ULT'] = 'ljopt/ir/ULT.lua',

        ['ljopt.ir.ALOAD'] = 'ljopt/ir/ALOAD.lua',
        ['ljopt.ir.AREF'] = 'ljopt/ir/AREF.lua',
        ['ljopt.ir.ASTORE'] = 'ljopt/ir/ASTORE.lua',
        ['ljopt.ir.BUFHDR'] = 'ljopt/ir/BUFHDR.lua',
        ['ljopt.ir.BUFPUT'] = 'ljopt/ir/BUFPUT.lua',
        ['ljopt.ir.BUFSTR'] = 'ljopt/ir/BUFSTR.lua',
        ['ljopt.ir.CALLL'] = 'ljopt/ir/CALLL.lua',
        ['ljopt.ir.CALLN'] = 'ljopt/ir/CALLN.lua',
        ['ljopt.ir.CNEW'] = 'ljopt/ir/CNEW.lua',
        ['ljopt.ir.CNEWI'] = 'ljopt/ir/CNEWI.lua',
        ['ljopt.ir.FLOAD'] = 'ljopt/ir/FLOAD.lua',
        ['ljopt.ir.FSTORE'] = 'ljopt/ir/FSTORE.lua',
        ['ljopt.ir.HLOAD'] = 'ljopt/ir/HLOAD.lua',
        ['ljopt.ir.HREF'] = 'ljopt/ir/HREF.lua',
        ['ljopt.ir.HREFK'] = 'ljopt/ir/HREFK.lua',
        ['ljopt.ir.HSTORE'] = 'ljopt/ir/HSTORE.lua',
        ['ljopt.ir.NEWREF'] = 'ljopt/ir/NEWREF.lua',
        ['ljopt.ir.SLOAD'] = 'ljopt/ir/SLOAD.lua',
        ['ljopt.ir.TNEW'] = 'ljopt/ir/TNEW.lua',

        ['ljopt.ir.CONV'] = 'ljopt/ir/CONV.lua',
        ['ljopt.ir.STRTO'] = 'ljopt/ir/STRTO.lua',
        ['ljopt.ir.TOBIT'] = 'ljopt/ir/TOBIT.lua',
        ['ljopt.ir.TOSTR'] = 'ljopt/ir/TOSTR.lua',

        ['ljopt.ir.NOP'] = 'ljopt/ir/NOP.lua',
   },
   install = {
      bin = {
         ljopt = 'bin/ljopt'
      }
   }
}
