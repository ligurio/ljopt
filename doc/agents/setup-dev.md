# Development setup

This document explains how to build ljopt dependencies, run the tests
and static analysis.

## Build

`make build` clones tarantool/luajit into `build/`, applies patches
from `lua_patches/` and builds LuaJIT. The LuaJIT commit is set by
`LUAJIT_TAG` in `Makefile`, and the same commit is used in `.envrc`.

`make test` also builds a second, old LuaJIT with known bugs
(`LUAJIT_BUGGY_TAG`), it is used by `tests/buggy_luajit_tests.lua`.

`make deps` installs Lua rocks required for development: `checks`,
`luacheck` and `luacov`.

The SMT solver libraries must be installed separately: cvc5 >= 1.2.0
and Z3 >= 4.15.3. See `.github/workflows/test.yaml` for the versions
used in CI.

## Tests

- `make test` runs all tests.
- `make test-z3-smoke` checks that the Z3 backend still works.
- `make coverage` runs tests with code coverage.

Useful environment variables, see `ljopt/config.lua`:

- `LJOPT_SMT` - SMT solver, `cvc5` (default) or `z3`.
- `LJOPT_SMT_TIMEOUT` - solver timeout in seconds.
- `LJOPT_LOOP_UNROLL_N` - loop unrolling limit.
- `LJOPT_STRICT` - strict mode.
- `LJOPT_DEBUG` - debug output.
- `LJOPT_DUMP_MODEL` - print a counterexample when a formula is SAT.

## Static analysis

`make check` runs `luacheck` and `luarocks lint` on the rockspec.
Both are enforced in CI.

---

If anything in this document seems outdated from how the code actually
works, then it must be immediately flagged to the user.
