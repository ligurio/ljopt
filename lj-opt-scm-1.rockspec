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
      ["lj-opt"] = "lj-opt/init.lua",
      ["lj-opt.unicode"] = "lj-opt/unicode.lua",
      ["lj-opt.utils"] = "lj-opt/utils.lua",
   },
}
