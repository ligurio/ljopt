package = 'ljopt'
version = 'scm-1'
source = {
    url = 'git+https://github.com/ligurio/ljopt',
    branch = 'devel',
}

description = {
    summary = 'Translate LuaJIT BC and IR to SMT',
    homepage = 'https://github.com/ligurio/ljopt',
    maintainer = 'Sergey Bronnikov <estetus@gmail.com>',
    license = 'MIT',
}

dependencies = {
    'luajit >= 2.1',
}

build = {
   type = "builtin",
   modules = {
      ["ljopt"] = "ljopt/init.lua",
      ["ljopt.unicode"] = "ljopt/unicode.lua",
      ["ljopt.utils"] = "ljopt/utils.lua",
   },
}
