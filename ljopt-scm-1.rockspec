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
        ["ljopt.ir_dump"] = "ljopt/ir_dump.lua",

        -- Everything related to SMT-LIB translation.
        ["ljopt.ir_smtlib"] = "ljopt/ir_smtlib/ir_smtlib.lua",

        --[[
            TODO: After several itterations of review and implementation create
            structure of modules based on class hierarchy.
            Check whether it's possible to separate all modules below
            to separate submodules with their own .rockspec (to improve granularity of code and reduce conflicts).
        ]]
        ["ljopt.ir_node_base"] = "ljopt/ir_smtlib/nodes/ir_node_base.lua",
        ["ljopt.ir_node"] = "ljopt/ir_smtlib/nodes/ir_node.lua",

        ["ljopt.ir_ADD"]  = "ljopt/ir_smtlib/nodes/arithmetic_ops/ir_ADD.lua"
        ["ljopt.ir_SUB"]  = "ljopt/ir_smtlib/nodes/arithmetic_ops/ir_SUB.lua"
        ["ljopt.ir_MUL"]  = "ljopt/ir_smtlib/nodes/arithmetic_ops/ir_MUL.lua"

        ["ljopt.smt_lib_context"] = "ljopt/ir_smtlib/smt_lib/smt_lib_context.lua",

   },
   install = {
      bin = {
         ljopt = "bin/ljopt"
      }
   }
}
