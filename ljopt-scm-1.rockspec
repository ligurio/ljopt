package = 'ljopt'
version = 'scm-1'
source = {
    url = 'git+https://github.com/ligurio/ljopt',
    branch = 'devel',
}

description = {
    summary = 'Translate LuaJIT BC and IR to SMT-LIB',
    homepage = 'https://github.com/ligurio/ljopt',
    maintainer = 'Sergey Bronnikov <estetus@gmail.com>',
    license = 'MIT',
}

dependencies = {
    "luajit >= 2.1.0"
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
