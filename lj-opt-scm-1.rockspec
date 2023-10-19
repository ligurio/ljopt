package = 'lj-opt'
version = 'scm-1'
source = {
    url = 'git+https://github.com/ligurio/lj-opt',
    branch = 'master',
}

description = {
    summary = 'Translate LuaJIT BC and IR to SMT',
    homepage = 'https://github.com/ligurio/lj-opt',
    maintainer = 'Sergey Bronnikov <estetus@gmail.com>',
    license = 'MIT',
}

dependencies = {
    'luajit >= 2.1',
}

build = {
   type = "builtin",
   modules = {
      luamut = "luamut/init.lua",
      ["luamut.unicode"] = "luamut/unicode.lua",
      ["luamut.unicode_printability_boundaries"] = "luamut/unicode_printability_boundaries.lua",
      ["luamut.utils"] = "luamut/utils.lua",
   },
}
