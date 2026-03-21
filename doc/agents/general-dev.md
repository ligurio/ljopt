# Development in ljopt

This document explains how to write code in ljopt: the expected
standards, style and other rules.

## Commits

- A commit contains only the required diff and a test that covers the
  changes.
- A commit is separated into a header and a body.
- The header has the format `system: imperative title`, for example
  `ljopt: support loop unrolling`. It is concise and its length is
  limited by 66 symbols.
- The body mentions all the changes done in the commit and explains
  why they are needed.
- Do not add `Co-Authored-By` or other attribution trailers for AI
  agents to commit messages.

## Code

- No regressions are introduced. If something worked before, it keeps
  working.
- Newly implemented modules are added to `ljopt-scm-1.rockspec`.
- Do not add new `assert()` for unreachable paths, use
  `utils.unreachable()` instead.
- Error messages are clear.

## Comments

Add comments only where the code is not self-explanatory. A comment
explains why the code is written this way, it does not narrate what
the next lines do.

- Comments must match the code. Update them together with the code.
- A comment is placed before the line it comments. A comment written
  as a separate sentence ends with a dot.

## Style

- Code lines are limited by 80 symbols, comment lines by 66 symbols,
  see `.luacheckrc`.
- Variable names are in `snake_case`.
- Lua supports `'` and `"` as quotes. They are unified within a file,
  but can be different in different files.
- Similar strings, as well as keys in Lua tables, are sorted in
  alphabetical order.

## Tests

- A newly implemented IR instruction has a test for it as a Lua chunk.
- Prefer chunks without loops, e.g. three calls of `foo()`, because
  they are faster. If a loop is needed, it includes the minimum number
  of iterations sufficient to record the trace in LuaJIT.
- A fixed LuaJIT bug gets a reproducer in `tests/reproducers/`.

---

If anything in this document seems outdated from how the code actually
works, then it must be immediately flagged to the user.
