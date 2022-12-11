### LuaJIT to SMT

#### Exporting BC/IR

- `string.dump(f [,strip])`
- `luajit -jbc=- foo.lua`
- `luajit -bl -e "a = a + 1"`
- `luajit -jdump=-m -O+loop -Ohotloop=1 -e "local b; for i = 1, 3 do b = 20 end"`

#### Parsing BC/IR

- https://github.com/LuaJIT/LuaJIT/blob/master/src/jit/dump.lua
- lbci, A Lua bytecode inspector library
	- http://webserver2.tecgraf.puc-rio.br/~lhf/ftp/lua/
	- https://github.com/LuaDist/lbci
- ldumplib, A bytecode dumper for Lua 4.0 http://webserver2.tecgraf.puc-rio.br/~lhf/ftp/lua/
- https://github.com/franko/luajit-lang-toolkit
- C: https://github.com/sztupy/luadec51
- https://gist.github.com/meepen/807dd81a572ffb0f28a8c44c04922fdd
- LuaJIT 2.1 Bytecode Parser https://github.com/imring/DisLua
- IR decompiler https://gitlab.com/znixian/luajit-decompiler

[^1]: https://luajit.org/running.html#opt_b
[^2]: https://luajit.org/extensions.html#string_dump
[^3]: http://web.archive.org/web/20220607041118/http://wiki.luajit.org/SSA-IR-2.0
[^4]: https://web.archive.org/web/20220717120825/http://wiki.luajit.org/Bytecode-2.0
