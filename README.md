### LuaJIT to SMT

#### Проекты для проверки эквивалентности кода для тестирования оптимизаций

- libfuzzer + solidity https://blog.soliditylang.org/2021/02/10/an-introduction-to-soliditys-fuzz-testing-approach/
- Solidity https://github.com/ethereum/solidity/tree/develop/test/formal
- https://github.com/kristerw/pysmtgcc/blob/main/smtgcc.py
- https://github.com/boogie-org/boogie
- https://github.com/p4gauntlet/gauntlet
- https://www.usenix.org/conference/osdi20/presentation/ruffy
- Alive2 для проверки оптимизаций https://web.ist.utl.pt/nuno.lopes/pubs.php?id=alive2-pldi21
- https://foss.heptapod.net/pypy/pypy/-/issues/3832
- https://github.com/MattPD/cpplinks/blob/master/compilers.correctness.md#verification
- > You can use Z3 to encode the source code before and after a compiler optimization as a logic formula and then check whether the formulae are equivalent. If they are not, there is likely a semantic bug in the transformation pass of your compiler, meaning you have introduced a subtle logic mistake.
- Z3 и SQL https://cosette.cs.washington.edu/
- https://github.com/SRI-CSL/llvm2smt#what-we-do

#### BC/IR documentation

- IR doc http://web.archive.org/web/20220607041118/http://wiki.luajit.org/SSA-IR-2.0
- BC doc https://web.archive.org/web/20220717120825/http://wiki.luajit.org/Bytecode-2.0
- IR decompiler https://gitlab.com/znixian/luajit-decompiler

#### Read BC/IR

- `string.dump(f [,strip])` generates portable bytecode
- https://luajit.org/extensions.html#string_dump
- `luajit -jbc=- foo.lua`
- `$ luajit -ble "a = a + 1"`
- https://luajit.org/running.html#opt_b

#### Parse BC/IR

- https://github.com/LuaJIT/LuaJIT/blob/master/src/jit/dump.lua
- lbci, A Lua bytecode inspector library
	- http://webserver2.tecgraf.puc-rio.br/~lhf/ftp/lua/
	- https://github.com/LuaDist/lbci
- ldumplib, A bytecode dumper for Lua 4.0
	- http://webserver2.tecgraf.puc-rio.br/~lhf/ftp/lua/
- https://github.com/franko/luajit-lang-toolkit
- C: https://github.com/sztupy/luadec51
- https://gist.github.com/meepen/807dd81a572ffb0f28a8c44c04922fdd
- LuaJIT 2.1 Bytecode Parser https://github.com/imring/DisLua
