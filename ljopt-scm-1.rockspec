package = 'ljopt'
version = 'scm-1'
source = {
    url = 'git+https://github.com/ligurio/ljopt',
    branch = 'devel',
}

description = {
    summary = 'Translate LuaJIT BC and IR to SMT-LIB',
    detailed = [[
	  ljopt is a bounded translation validation tool for the LuaJIT bytecode
      and intermediate representation (IR). It limits resource consumption by,
	  for example, unrolling loops up to some bound, which means
      there are circumstances in which it misses bugs. ljopt is
      designed to avoid false alarms, is fully automatic through
      the use of an SMT solver, and requires no changes to LuaJIT.
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
      ["ljopt.dump_bc"] = "ljopt/dump_bc.lua",
      ["ljopt.dump_ir"] = "ljopt/dump_ir.lua",
      ["ljopt.parse_bc"] = "ljopt/parse_bc.lua",
      ["ljopt.parse_ir"] = "ljopt/parse_ir.lua",
      ["ljopt.smtlib_bc"] = "ljopt/smtlib_bc.lua",
      ["ljopt.smtlib_ir"] = "ljopt/smtlib_ir.lua",
   },
   install = {
      bin = {
         ljopt = "bin/ljopt"
      }
   }
}
