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

build = {
    type = "builtin",
    modules = {
        ljopt = "ljopt/init.lua",
        ["ljopt.main"] = "ljopt/main.lua",
        ["ljopt.bc_dump"] = "ljopt/bc_dump.lua",
        ["ljopt.bc_smtlib"] = "ljopt/bc_smtlib.lua",
        ["ljopt.ir_dump"] = "ljopt/ir_dump.lua",
        ["ljopt.ir_smtlib"] = "ljopt/ir_smtlib.lua",

        ["ljopt.ir.ir_node_base"] = "ljopt/ir/ir_node_base.lua",
        ["ljopt.ir.ir_node_dummy"] = "ljopt/ir/ir_node_dummy.lua",
        ["ljopt.ir.ir_nodes"] = "ljopt/ir/ir_nodes.lua",
        ["ljopt.ir.smt_context"] = "ljopt/ir/smt_context.lua",

        ["ljopt.ir.ADD"] = "ljopt/ir/ADD.lua",
        ["ljopt.ir.BAND"] = "ljopt/ir/BAND.lua",
        ["ljopt.ir.BROL"] = "ljopt/ir/BROL.lua",
        ["ljopt.ir.CONV"] = "ljopt/ir/CONV.lua",
        ["ljopt.ir.EQ"] = "ljopt/ir/EQ.lua",
        ["ljopt.ir.FLOAD"] = "ljopt/ir/FLOAD.lua",
        ["ljopt.ir.LE"] = "ljopt/ir/LE.lua",
        ["ljopt.ir.MUL"] = "ljopt/ir/MUL.lua",
        ["ljopt.ir.NE"] = "ljopt/ir/NE.lua",
        ["ljopt.ir.NOP"] = "ljopt/ir/NOP.lua",
        ["ljopt.ir.SLOAD"] = "ljopt/ir/SLOAD.lua",
        ["ljopt.ir.SUB"] = "ljopt/ir/SUB.lua",
        ["ljopt.ir.ULE"] = "ljopt/ir/ULE.lua",
   },
   install = {
      bin = {
         ljopt = "bin/ljopt"
      }
   }
}
