package = 'ljopt'
version = 'scm-1'
source = {
    url = 'git+https://github.com/ligurio/ljopt',
    branch = 'devel',
}

description = {
    summary = 'Translate LuaJIT BC and IR to SMT-LIB',
    detailed = [[
ljopt is a bounded translation validation tool for the LuaJIT bytecode and
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
        ['ljopt.bc_dump'] = 'ljopt/bc_dump.lua',
        ['ljopt.bc_smtlib'] = 'ljopt/bc_smtlib.lua',
        ['ljopt.dev_checks'] = 'ljopt/dev_checks.lua',
        ['ljopt.ir.SNAP'] = 'ljopt/ir/SNAP.lua',
        ['ljopt.ir_dump'] = 'ljopt/ir_dump.lua',
        ['ljopt.ir_dump_utils'] = 'ljopt/ir_dump_utils.lua',
        ['ljopt.ir_smtlib'] = 'ljopt/ir_smtlib.lua',
        ['ljopt.main'] = 'ljopt/main.lua',
        ['ljopt.smt_constants'] = 'ljopt/smt_constants.lua',
        ['ljopt.utils'] = 'ljopt/utils.lua',

        ['ljopt.ir.arith_utils'] = 'ljopt/ir/arith_utils.lua',
        ['ljopt.ir.ir_node_base'] = 'ljopt/ir/ir_node_base.lua',
        ['ljopt.ir.ir_node_dummy'] = 'ljopt/ir/ir_node_dummy.lua',
        ['ljopt.ir.ir_nodes'] = 'ljopt/ir/ir_nodes.lua',
        ['ljopt.ir.smt_context'] = 'ljopt/ir/smt_context.lua',

        ['ljopt.ir.BinOp'] = 'ljopt/ir/BinOp.lua',
        ['ljopt.ir.UnOp'] = 'ljopt/ir/UnOp.lua',

        ['ljopt.ir.ADD'] = 'ljopt/ir/ADD.lua',
        ['ljopt.ir.ADDOV'] = 'ljopt/ir/ADDOV.lua',
        ['ljopt.ir.DIV'] = 'ljopt/ir/DIV.lua',
        ['ljopt.ir.FPMATH'] = 'ljopt/ir/FPMATH.lua',
        ['ljopt.ir.MOD'] = 'ljopt/ir/MOD.lua',
        ['ljopt.ir.MUL'] = 'ljopt/ir/MUL.lua',
        ['ljopt.ir.SUB'] = 'ljopt/ir/SUB.lua',

        ['ljopt.ir.BAND'] = 'ljopt/ir/BAND.lua',
        ['ljopt.ir.BNOT'] = 'ljopt/ir/BNOT.lua',
        ['ljopt.ir.BOR'] = 'ljopt/ir/BOR.lua',
        ['ljopt.ir.BROL'] = 'ljopt/ir/BROL.lua',
        ['ljopt.ir.BROR'] = 'ljopt/ir/BROR.lua',
        ['ljopt.ir.BSAR'] = 'ljopt/ir/BSAR.lua',
        ['ljopt.ir.BSHL'] = 'ljopt/ir/BSHL.lua',
        ['ljopt.ir.BSHR'] = 'ljopt/ir/BSHR.lua',
        ['ljopt.ir.BXOR'] = 'ljopt/ir/BXOR.lua',

        ['ljopt.ir.EQ'] = 'ljopt/ir/EQ.lua',
        ['ljopt.ir.GE'] = 'ljopt/ir/GE.lua',
        ['ljopt.ir.GT'] = 'ljopt/ir/GT.lua',
        ['ljopt.ir.LE'] = 'ljopt/ir/LE.lua',
        ['ljopt.ir.LT'] = 'ljopt/ir/LT.lua',
        ['ljopt.ir.NEG'] = 'ljopt/ir/NEG.lua',
        ['ljopt.ir.NE'] = 'ljopt/ir/NE.lua',
        ['ljopt.ir.UGE'] = 'ljopt/ir/UGE.lua',
        ['ljopt.ir.UGT'] = 'ljopt/ir/UGT.lua',
        ['ljopt.ir.ULE'] = 'ljopt/ir/ULE.lua',
        ['ljopt.ir.ULT'] = 'ljopt/ir/ULT.lua',

        ['ljopt.ir.FLOAD'] = 'ljopt/ir/FLOAD.lua',
        ['ljopt.ir.SLOAD'] = 'ljopt/ir/SLOAD.lua',

        ['ljopt.ir.CONV'] = 'ljopt/ir/CONV.lua',

        ['ljopt.ir.NOP'] = 'ljopt/ir/NOP.lua',
   },
   install = {
      bin = {
         ljopt = 'bin/ljopt'
      }
   }
}
