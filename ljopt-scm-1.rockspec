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

-- dependencies = {
--     "luajit >= 2.1"
-- }

external_dependencies = {
    LUAJIT = {
        header = 'luajit-2.1/luajit.h',
    },
}

build = {
    type = "builtin",
    modules = {
        ljopt = "ljopt/init.lua",
        ["ljopt.main"] = "ljopt/main.lua",
        ["ljopt.bc_dump"] = "ljopt/bc_dump.lua",
        ["ljopt.bc_smtlib"] = "ljopt/bc_smtlib.lua",
        ["ljopt.bc_parse"] = "ljopt/bc_parse.lua",
        ["ljopt.ir_dump"] = "ljopt/ir_dump.lua",
        ["ljopt.ir_smtlib"] = "ljopt/ir_smtlib.lua",
        ["ljopt.ir_parse"] = "ljopt/ir_parse.lua",
   },
   install = {
      bin = {
         ljopt = "bin/ljopt"
      }
   }
}
