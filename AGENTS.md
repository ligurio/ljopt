## ljopt

ljopt is a bounded translation validation tool for the LuaJIT
intermediate representation (IR). It checks that LuaJIT JIT
optimizations do not change the semantics of a recorded trace.

The tool runs a Lua chunk twice: with JIT optimizations disabled and
enabled. The recorded traces and their snapshots are translated to an
SMT-LIB formula which states that the snapshots of both traces
differ. The formula is UNSAT when the optimized trace is equivalent to
the unoptimized one. A SAT result means a solver found an input where
the traces diverge, that is, a possible miscompilation.

The analysis is bounded: loops are unrolled up to some limit, so ljopt
can miss bugs, but it is designed to avoid false alarms.

The project is written in Lua and runs on LuaJIT. LuaJIT is built from
the tarantool/luajit fork with patches from `lua_patches/`. The SMT
solvers are cvc5 (default) and Z3.

### Structure

- `bin/ljopt` is the command line entry point, see `ljopt/main.lua`.
- `ljopt/init.lua` is the public Lua API.
- `ljopt/runtime.lua` records traces of a Lua chunk in a sandbox.
- `ljopt/ir_dump.lua` dumps IR, it is borrowed from LuaJIT and must be
  kept close to upstream.
- `ljopt/ir_smtlib.lua` translates traces and snapshots to SMT-LIB.
- `ljopt/ir_passes.lua` has IR analysis passes that run before SMT-LIB
  emission.
- `ljopt/loop_unrolling.lua` unrolls loops in traces.
- `ljopt/ir/` has a module per IR instruction, named after the
  instruction (`ADD.lua`, `HREFK.lua`, etc.), plus shared helpers.
- `ljopt/config.lua` holds the options set by `LJOPT_*` environment
  variables.
- `ljopt-scm-1.rockspec` lists all modules of the project.
- `tests/` has all the tests.

### Testing

- `tests/ir_tests.lua` translates single IR instructions with known
  inputs and checks the result against the expected value in SMT.
- `tests/tests.lua` has end-to-end tests: a Lua chunk is recorded,
  translated, and the expected IR instructions and formulas are
  checked.
- `tests/unit_tests.lua` has unit tests for internal modules.
- `tests/buggy_luajit_tests.lua` runs reproducers from
  `tests/reproducers/` for known LuaJIT bugs on an old buggy LuaJIT,
  where ljopt must find them, and on the current one.

All tests are run by `make test`, static analysis by `make check`.

### Task-specific guidance

The files under `doc/agents/` hold task-specific knowledge, the
agent-agnostic equivalent of Claude Code "skills".

**Do not read these files up front.** Load a file only when the
current task matches its description below, and only the matching
ones.

- `doc/agents/general-dev.md` - Standards for writing and reviewing
  ljopt patches: commit structure and message format, tests, comments
  and code style. MUST use when writing or editing code and
  committing.

- `doc/agents/review.md` - Code review: validation of commits and code
  for correctness and against the project standards. MUST use when
  the user asks to review a patch, a branch or a pull request.

- `doc/agents/setup-dev.md` - Building LuaJIT, installing dependencies,
  running tests and static analysis. MUST use when you need to build
  or test the project.

---

If anything in the overview seems outdated from how the code actually
works, then it must be immediately flagged to the user.
