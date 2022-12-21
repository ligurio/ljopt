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
> You can use Z3 to encode the source code before and after a compiler
> optimization as a logic formula and then check whether the formulae are
> equivalent. If they are not, there is likely a semantic bug in the
> transformation pass of your compiler, meaning you have introduced a subtle
> logic mistake.
- Z3 и SQL https://cosette.cs.washington.edu/
- https://github.com/SRI-CSL/llvm2smt#what-we-do
- PyPy https://www.pypy.org/posts/2022/12/jit-bug-finding-smt-fuzzing.html
