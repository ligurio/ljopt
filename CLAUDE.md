# ljopt

LuaJIT trace optimizer equivalence verifier. Records JIT traces twice
(unoptimized + optimized), translates each to SMT-LIB, asserts the two
traces are inequivalent, and lets z3 prove `unsat` (=> equivalent) or
return a `sat` counterexample.

## Build / run

- `make test` runs the full suite. Needs z3 on `LD_LIBRARY_PATH`.
- Local z3 used in this workspace: `../z3/build/z3` with
  `LD_LIBRARY_PATH=../z3/build`. The system z3 is too old / lacks
  some sorts.
- LuaJIT builds are checked out into `build/luajit_<sha>/`. The buggy
  fork (older sha + `~`) is needed for `buggy_luajit_tests.lua`.
- Entry point for ad-hoc runs: `ljopt/main.lua <file.lua>` — emits SMT
  to stdout. `t.lua`/`t.smt`/`t2.smt` in the repo root are scratch
  scratch artifacts from this workflow (not checked-in inputs).

## SMT encoding model

Per trace pair, three top-level array variables are declared:

- `shared_mem_stack<id>` — the "ground truth" pre-trace memory.
- `mem_unopt<id>` — unopt-trace memory.
- `mem_opt<id>` — opt-trace memory.

Each is a `MemPtr = Array Int (Array Int (Array MemCell MemCell))`,
indexed `[ptr][version][key]`. Versions advance on every store; reads
go through `mem_ver_<name>` which maps `[ptr] -> current version`.

`MemCell` is a 5-constructor ADT: `int-val | fp-val | str-val |
tab-val | p32-val`. Constructor accessors (`get-tab`, `get-fp`, ...)
return *unconstrained* values when called on the wrong constructor —
this is the source of several subtle equivalence-check bugs.

### Initial-state tying

`MemoryStack:allocate(slot)` (called by `SLOAD TAB/CDT/FUN`) emits
`(= shared[base_slot][0] mem_X[local_slot][0])` so SLOAD'd tables
are pinned to the same ground state across both traces.

`MemoryStack:load(ptr)` (added later) emits a lazy tie
`(= shared[ptr][0] mem_X[ptr][0])` for any *dynamic* ptr read. This
catches transitively-reached tables (e.g. `env.math.pi`) where the
ptr is an expression like `(get-p32-tab op[N])` and the int value is
only known to the solver. Dedup is by exact ptr-expression string,
and static literal ptrs are skipped (`tonumber(ptr) ~= nil`).
Implementation: `ljopt/ir/smt_context.lua` — `MemoryStack:load` and
`flush_pending`.

Callers must `flush_pending()` after any `load`/`load_index` and
prepend the result to the SMT chunk they emit. Sites that do this:
`HLOAD/HSTORE/ALOAD/ASTORE/FLOAD/FSTORE/BUFPUT/BUFSTR/CALLL/SNAP`.

### Type-constructor pinning

Typed loads (`HLOAD str/num/tab`, `FLOAD tab`, `ALOAD tab`) emit
`(assert ((_ is X-val) raw_cell))` on the read cell. Without this,
the solver picks the wrong constructor, the ADT accessor becomes a
free variable, and chains diverge across traces — producing
spurious `sat`.

Historically `HLOADTab/ALOADTab` wrapped the result in
`(ite (is tab-val cell) (get-tab cell) fresh_slot)`. `fresh_slot` is
a `MemoryStack:alloc_slot()` counter — **distinct between unopt and
opt MemoryStacks** (4 vs 2 in one failure). The hard type-assert
makes the ite fallback dead; the unwrapped `(get-tab cell)` form is
fine and faster for z3.

## Known limitations / gotchas

- z3 HORN (SPACER) backend doesn't support FP or Strings — only Int,
  Real, BV, Bool, ADTs. Don't try to feed this encoding to HORN.
- Equivalence-check disjunct is at the bottom of every emitted SMT:
  `(or (not (= lsb(snap_te_unopt) lsb(snap_te_opt))) <slot-diff>...
       <memory-diff>)`. `sat` means at least one disjunct is
  satisfiable; debug by `(get-value ...)` on each piece.
- FP commutativity (e.g. `cos_lit + pi == pi + cos_lit`) IS provable
  by z3 — when an `sat` looks like an fp-algebra issue, suspect ADT
  / ptr-divergence first.
## Test corpus (`../ljopt-tests/moonsmith/`)

~120k generated `<id>.lua` files. `fix_neg_zero.py` rewrites
`<op> - -<op>` to `<op> + <op>` in-place; preserves Lua comments
(both `--` and `--[[ ]]`), strings, and unary contexts after Lua
keywords (`or - -X` stays as a unary expression). The two-dash
match requires whitespace between the dashes so `-- comment` is
never touched.

## Repo conventions

- Long expressions: closing `)` on its own line (see project memory).
- Tests live in `tests/`; entry points `tests.lua`,
  `unit_tests.lua`, `ir_tests.lua`, `buggy_luajit_tests.lua`.
- `tests/tests.lua` has a big `srcs` table near the end driving the
  generic "ins present + parse + check unsat" suite; add new
  globals/memory cases there.
