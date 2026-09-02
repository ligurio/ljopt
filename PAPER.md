# PAPER.md — running notes for the ljopt paper

Living scratchpad for everything paper-related: venue decisions, the
argument we are making, measured numbers, and the idea backlog. The
LaTeX itself lives in `paper/` (one `main.tex`, one build mode per
venue). Numbers here are the ones cleared for citation; anything not
listed as measured is not yet safe to put in the paper.

Last updated: 2026-08-31.

---

## 1. The thesis

The paper's centre of gravity is *not* "we built an SMT-based
equivalence checker for LuaJIT". Translation validation is old (Pnueli
1998, Necula 2000, Alive2 2021) and a reviewer will say so. The claim
that is actually ours, and that a compiler audience cares about, is:

> **Program-level fuzzing cannot reach a tracing JIT's optimizer.**
> Generating Lua programs and running them exercises 37.5% of LuaJIT's
> optimizer. Replaying synthetic IR directly through the same FOLD
> engine reaches 97.5% — including all but two of the lines the
> programs reach, plus 1,509 they never reach.

Everything else in the paper — the SMT encoding, the oracles, the bugs
— is what makes that replay *checkable* rather than merely fast. Lead
with the coverage result; introduce the encoding as the machinery that
turns coverage into verdicts.

Corollary worth stating explicitly, because it is the generalisable
lesson: the bottleneck in JIT optimizer testing is not the oracle, it
is *reachability*. A program-level generator spends its budget in the
interpreter and the recorder; the optimizer only ever sees the narrow
band of IR that real recorded traces happen to produce.

---

## 2. Measured results (2026-08-31)

Both arms measured in one session, on the same gcov-instrumented build
(`build/luajit_cov`, built 2026-08-25), same six files, same
denominators. This is an apples-to-apples comparison, not a number
lifted from an old README.

### Headline table

| file | lines | corpus | irfuzz |
|---|---|---|---|
| `lj_opt_fold.c`   | 1241 | 330 (26.6%) | 1209 (97.4%) |
| `lj_opt_mem.c`    |  572 | 202 (35.3%) |  554 (96.9%) |
| `lj_opt_loop.c`   |  245 | 228 (93.1%) |  239 (97.6%) |
| `lj_opt_dce.c`    |   35 |  35 (100%)  |   35 (100%)  |
| `lj_opt_sink.c`   |  148 |  80 (54.1%) |  145 (98.0%) |
| `lj_opt_narrow.c` |  272 |  67 (24.6%) |  267 (98.2%) |
| **TOTAL**         | **2513** | **942 (37.5%)** | **2449 (97.5%)** |

- Corpus arm: all **120,690** moonsmith programs from
  `../ljopt-tests/moonsmith/`, JIT on at `-O3` with `hotloop=3
  hotexit=3 tryside=3` (thresholds lowered deliberately in the
  baseline's favour, so short generated programs still compile). Every
  file ran clean: 120,690 ok, 0 errors, 0 timeouts, ~8 min wall.
- irfuzz arm: full `covrun.lua` sweep, every mode with and without
  `COV_LOOP`, capped at 8000 traces. Reproduces
  `ljopt/irfuzz/README.md` line for line.

### Saturation curve (corpus arm)

The baseline is not starved — it is *saturated*. Coverage as programs
accumulate:

| programs | lines | % |
|---|---|---|
| 500 | 736 | 29.3% |
| 2,000 | 774 | 30.8% |
| 8,000 | 870 | 34.6% |
| 30,000 | 904 | 36.0% |
| 120,690 | 942 | 37.5% |

The last 90,690 programs bought **38 lines**. This is the figure that
kills the obvious reviewer objection ("your baseline just needed a
bigger corpus"). Plot it.

### Set comparison

| | lines |
|---|---|
| reached by corpus only | **2** |
| reached by irfuzz only | **1,509** |
| reached by both | 940 |
| union | 2,451 (97.5%) |
| neither | 62 |

IR replay nearly *subsumes* 120k generated programs.

### The two corpus-only lines — an honest finding, and actionable

`lj_opt_mem.c:198` and `lj_opt_mem.c:863`. Both are the same shape: an
aliasing path guarded by `irt_isnum` on a **table key**, i.e. reached
only when a program writes a float-keyed table entry (`t[1.5] = v`).

- 198: AREF store-forwarding bails to `cselim` when a `NEWREF` in the
  chain has a num-typed key.
- 863: TLEN's conflicting-store search stops at a num-typed hash key.

irfuzz cannot reach these *by construction*: `enum.lua` draws array
indices and hash keys from disjoint **integer** ranges (positive vs
negative), because LuaJIT's array and hash parts are separate address
spaces and ljopt keys both by value. No float key is ever generated.

Two ways to use this:

1. **Fix it.** Add a num-typed hash key to `iter_alias`/`iter_ahref`;
   that should take irfuzz to 2451/2513 and make the subsumption
   total. Do this before submitting if time allows — "our replay
   strictly subsumes 120k programs" is a much cleaner sentence.
2. **Keep it as the honesty paragraph.** The baseline was not just a
   number to beat; it found a real gap in our generator. That is a
   genuinely good look for a tool paper, and reviewers reward it.

Either way, say it. Do not quietly round 2 lines away.

### Solver cost (measured 2026-08-31)

Everything in the coverage comparison above **skips the solver** by
design — `covrun.lua` exists to drive the generators without solving, and
the corpus arm only runs programs under the JIT. So the 8-minute and
3-minute figures are *generator* cost, not verification cost. Do not
present them as verification cost; that is exactly the conflation a
reviewer would catch.

**This replaces the old 25-seed comparison** (cvc5 20/25 in 127 s vs z3
18/25 in 165 s). Do not cite that number again: 25 seeds is too thin, and
`irfuzz/fuzz.lua`'s own comments record that it produced contradictory
conclusions twice. The run below is 180 byte-identical queries, 30 each
from random / tables / narrow / alias / guard / mixed, 30 s limit, both
solvers on the same inputs.

| | cvc5 1.3.5.dev | z3 5.1.0 |
|---|---|---|
| closed | **166 / 180 (92.2%)** | 134 / 180 (74.4%) |
| unknown | 14 | 46 |
| sat / error | 0 / 0 | 0 / 0 |
| median | 0.94 s | **0.33 s** |
| median, closed only | 0.90 s | **0.16 s** |
| mean | **5.00 s** | 9.45 s |
| p90 | **20.4 s** | 30.0 s (the limit) |
| total wall | **15.0 min** | 28.3 min |

The shape of the two solvers is different, and that is the finding worth
stating: **z3 is fast-or-never, cvc5 grinds.** z3's median is three times
faster (0.33 s vs 0.94 s) — on the queries it can do, it is quicker — but
it gives up on more than a quarter of them, so its *mean* is nearly twice
cvc5's and its total wall time is nearly double. A median alone would
have ranked z3 first and been badly wrong. Report median *and* closure
rate together, or the comparison misleads.

Head to head on those 180: union 171, **cvc5-only 37, z3-only 5.**

End-to-end on real corpus programs, translation vs solving:

| program | SMT emitted | translate | solve | verdict |
|---|---|---|---|---|
| 24047.lua | 82 KB | 0.029 s | 4.69 s | unsat |
| 20871.lua | 41 KB | 0.070 s | 0.78 s | unsat |

**Solving costs roughly 100x translation.** Recording, IR capture and
SMT-LIB emission are essentially free; the solver is the entire cost of
the tool. Say this in the paper — it is what justifies the sound
pre-filters (byte-identical and commutative-swap skipping) as more than
micro-optimisations, and it explains why a coverage sweep can afford 8000
traces per mode while a solver campaign over the same space cannot.

**Caveat on these latencies.** The box was running four other
solver-heavy jobs from concurrent sessions (two irfuzz sweeps ~9 h in, a
`--narrow` z3 sweep, a diffuzz run) — about 5 of 32 cores busy. CPU
contention was therefore minimal but memory-bandwidth contention was not
zero. Absolute numbers may be slightly inflated; the cvc5/z3 comparison
is at least consistently affected. **Re-run on an idle box before
citing.**

### Solver bugs found by these formulas (verified 2026-08-31)

ljopt's formulas mix QF_FP, bitvectors, arrays, datatypes and strings in
one query — a combination almost nothing in the standard benchmark sets
covers. That makes them unusually good solver stress tests, and it has
found real defects in both solvers.

**cvc5 1.1.2 — unsound model. Confirmed and reproduced today.**
On narrow-mode queries, cvc5 1.1.2 answers `sat` where current main
answers `unsat`, and with `--check-models` it aborts (SIGABRT) rejecting
the model it had just produced:

```
Fatal failure within CheckModels::checkModel at ./src/smt/check_models.cpp:146
Internal error detected SolverEngine::checkModel():
  ERRORS SATISFYING ASSERTIONS WITH MODEL:
assertion:     (= (select op_unopt1 7)
                  (int-val ((_ sign_extend 32) ((_ extract 31 0)
                    ((_ fp.to_sbv 64) roundTowardZero
                      (get-fp (select op_unopt1 6)))))))
simplifies to: false
expected `true'.
```

The trigger shape is `fp.to_sbv` composed with ADT accessors and array
selects — which is why *only* narrow-mode queries trip it (alias, guard
and mixed were all clean). Three of thirty narrow queries reproduce it
(`narrow_00009`, `_00011`, `_00012` in the dumped set).

Status: **fixed in current main** (1.3.5.dev, git `ed5e08073`), so there
is nothing to report upstream. Cite it as evidence that the encoding
stresses solvers in a corner they under-test, not as an open bug. The
honest framing: *cvc5's own model checker caught it* — which is the same
discipline ljopt applies to itself.

This was already known in-tree (`tests/smtlib2_cvc5.lua:11` records it)
but was never written down as a finding; TROPHIES.md lists only LuaJIT
bugs.

Together with Z3#9488 (invalid model, §7) this is two independent
solver-unsoundness findings from the same formula family. That is a
genuine paper point and it motivates keeping the encoding portable across
two solvers: the trust base is a moving target.

**Differential cvc5 vs z3, 1470 queries — no bug, but a real result.**
Seven pass surfaces (random, tables, alias, guard, mixed, sink, narrow),
both solvers self-validating (`--check-models` / `model_validate=true`),
15 s limit:

| | |
|---|---|
| agree | 1142 |
| differ in strength only | 328 |
| **sat/unsat disagreement** | **0** |
| **self-check flags** | **0** |

Zero disagreements is a soundness cross-check passing, not a null result:
on 1470 formulas mixing FP, BV, arrays, ADTs and strings, two independent
solvers never contradicted each other and neither ever produced a model
it could not defend.

The 328 strength differences split **276 cvc5-closes / 52 z3-closes**,
and they are not spread evenly — they localise almost entirely to one
surface:

| surface | n | cvc5 closed | z3 closed |
|---|---|---|---|
| `narrow` | 600 | **93.3%** | 57.2% |
| `tables` | 150 | 68.0% | 67.3% |
| `random` | 150 | 57.3% | 52.0% |
| `mixed` | 150 | 98.0% | **99.3%** |
| `alias` | 150 | 100% | 100% |
| `guard` | 150 | 100% | 100% |
| `sink` | 120 | 100% | 100% |

**Narrow is the whole story: a 36-point gap, 225 of cvc5's 276 wins.**
Narrow is the only enumerator that emits `fp.to_sbv` sinks — the same
construct that broke cvc5 1.1.2 — so FP→BV reasoning is simultaneously
the hardest surface for both solvers and the one where they differ most.
That is a coherent, mechanistic story, not a benchmark artifact.

z3 is not merely worse: its 52 wins concentrate in `tables` (25) and
`random` (17), and 5 of the 180-query set are closed by z3 alone. Union
across both solvers is **1367/1470 (93.0%)** against cvc5's 1330 alone.
So keeping two backends buys real coverage — a smaller effect than the
draft's "portability doubled as a soundness review" implies, but a
measured one. State it as: *cvc5 is the better default by a wide margin
on this encoding; z3 remains worth running as a cross-check because it
closes queries cvc5 cannot, and because the two have never disagreed.*

**Negative result: current cvc5 is clean on the shape that broke 1.1.2.**
600 narrow-mode queries against 1.3.5.dev with `--check-models`: 564
unsat, 36 unknown at a 20 s limit, **zero** flagged. Report this
alongside the finding — it is the same discipline the paper already
applies to fault injection, and it stops the 1.1.2 result from reading as
an attack on cvc5. The 36/600 (6%) unknown rate on narrow mode is itself
worth citing as the hardest surface for the solver.

**Methodological note worth a sentence in the paper.** Validating the
differential harness against cvc5 1.1.2 showed that z3 answers `unknown`
on the very queries where 1.1.2 is unsound — so a pure verdict
differential would have *missed* the bug, and only `--check-models`
caught it. For this formula family the two solvers differ on *strength*
far more often than on truth, which makes model self-validation the more
sensitive detector and cheap to leave on permanently. A tool paper
claiming to cross-check two solvers should say which of the two
mechanisms is actually doing the work.

Scripts: `scripts/hunt_solver_bugs.sh` (single solver + self-check),
`scripts/diff_solvers.sh` (cvc5 vs z3, both self-validating).

### Reproducing

```sh
# corpus list (deterministic shuffle)
find <corpus> -name '*.lua' | sort | shuf --random-source=<(yes 42) \
  > build/cov/corpus.list

find build/luajit_cov -name '*.gcda' -delete
scripts/cov_corpus.sh 1 120690          # baseline arm, ~8 min
scripts/cov_report.sh
cp build/luajit_cov/src/lj_opt_*.c.gcov build/cov/corpus/

find build/luajit_cov -name '*.gcda' -delete
scripts/cov_irfuzz.sh                   # IR-replay arm, ~3 min
scripts/cov_report.sh
cp build/luajit_cov/src/lj_opt_*.c.gcov build/cov/irfuzz/

python3 scripts/cov_compare.py build/cov/corpus build/cov/irfuzz
```

Gotcha worth keeping: the notes files are GCC 11.1 (`B11`) but the box
has 11.5 and 13.3. `gcov-11` reads them with a version warning and the
totals are correct; `gcov-13` refuses and silently reports zero
executable lines. Also, gcov must run *from* the LuaJIT source dir and
be handed the `.gcno` path — CMake's `lj_opt_fold.c.o` naming means a
bare `foo.c` argument makes gcov look for the wrong notes file.

---

## 3. Venue

### Decision: CGO 2027, Round 2, **Tool paper**

| | |
|---|---|
| Deadline | **2026-09-10**, 23:59:59 AoE |
| Rebuttal | Oct 20–22, 2026 |
| Notification | **2026-11-02** |
| Conference | Salt Lake City, Mar 20–24, 2027 |
| Format | ACM, **11 pages of text** excl. bibliography |
| Review | **double-blind** |
| Tool track | title prefixed `Tool:`; **artifact evaluation mandatory** |

Why CGO over TACAS, despite TACAS being the better topical fit:
notification lands **before December PhD application deadlines**. An
acceptance in hand while applications are open is worth more than a
higher acceptance probability that resolves in January.

**The two are mutually exclusive.** TACAS 2027 closes 2026-10-15,
which is *before* the CGO notification on 11-02. Submitting to both is
concurrent submission and is forbidden. Pick one, and if CGO rejects,
the natural fallback is CC 2027 (co-located with CGO, deadline in the
November window) or VMCAI 2027.

Post an arXiv preprint regardless — SIGPLAN policy permits preprints
under double-blind, and it gives something citable in applications
whatever the outcome. Do not publicise it during review.

### Honest odds

As a **regular research paper**: weak. Known technique, single target,
no performance story, modest bug count. As a **Tool paper**: a real
fit — the official criteria are "applying CGO technology to real-world
problems", public availability, functional artifact backing every
claim. Estimate 30–40%. The coverage result above is what moves it
from "engineering writeup" to "paper with a result".

### Weaknesses to pre-empt in the writing

- **Single target.** No evidence it transfers to V8/SpiderMonkey. Best
  available answer: the mechanism needs only an IR plus a fold engine,
  and the LuaJIT-side patch is 335 lines of C. Argue it; don't
  overclaim it.
- **Bug count is modest** (4 new). Counter by weighting: one has an
  authored fix, one is a reported upstream issue, and the 35-case
  historical corpus shows the checker catches real regressions
  (sat on buggy build, unsat on fixed).
- **Self-referential evaluation.** The corpus baseline above is
  precisely the fix for this. It is the only external comparison the
  paper has — make it prominent.
- **No speedup.** Unavoidable at CGO. Frame the contribution as
  compiler *reliability* and lean on the reachability lesson.

---

## 4. Outline (target: 11 pages ACM)

1. **Introduction** — tracing JITs; optimizer bugs are observable in
   production Lua; lead with the 37.5% vs 97.5% result.
2. **Background** — LuaJIT pipeline (record → IR → FOLD/mem/loop/sink/
   narrow → mcode); SMT-LIB theories used (FP, BV, Arrays, ADTs,
   Strings; no quantifiers).
3. **Translation validation** — double recording at `jit.opt.start(0)`
   vs `(3)`, hotloop=1, forked `dump.lua` capturing IR via
   `jit.util.traceir/tracek/tracesnap`; the encoding; table identity;
   the three type-pinning disciplines; guards/snapshots; the final
   equivalence disjunct; FP fidelity; soundness engineering
   (vacuous-unsat fixes, `VERIFY_LJOPT_CORRECTNESS`, NYI weakening).
4. **irfuzz — IR-level fuzzing** (centrepiece) — the 335-line
   `jit.util.irfuzz` patch replaying synthetic typed IR through the
   real FOLD engine twice (flags 0 vs `JIT_F_OPT_DEFAULT`);
   deterministic LCG generation with a *blacklist* op menu; exhaustive
   enumeration (`enum.lua`, 17 `iter_*` families); oracle reuse
   (`compare_trace_records`, same as the recorded path); sound
   pre-filters; loop mode; the third syntactic oracle
   (`lint_conv_types`) catching LJ#524-class bugs invisible to SMT.
5. **diffuzz** — end-to-end interpreter-vs-JIT differential fuzzer;
   exact-int-mod-1000003 oracle; per-pass-disabled configs double as
   bisection. Frame with §4 and the linter as *layered oracles*.
6. **Evaluation** — §2 coverage comparison first; then solver cost and
   the cvc5/z3 comparison (§2, 180- and 1470-query runs); then bugs;
   then non-vacuity by fault injection.
7. **Limitations** — backend out of scope; memory compared only at
   final version; bounded unrolling; NYI weakening; uninterpreted
   congruence; escaping-table dead-store spurious sat; solver quirks.
8. **Related work** — Pnueli, Necula, Alive/Alive2, CompCert, CSmith,
   EMI, Fuzzilli, FuzzJIT, cvc5, z3.
9. **Conclusion + availability.**

---

## 5. Numbers cleared for citation

Verified against branch `aleksisch/ins-fuzzer-cvc5` @ 74b1317.

- Coverage: everything in §2 above (measured 2026-08-31).
- Solvers: the 180-query and 1470-query runs in §2. **The old 25-seed
  figure (20/25 vs 18/25) is superseded — do not cite it.**
- Bug corpus: 35 cases; 38 reproducers over ~30 issues.
- Re-detected upstream bugs: LJ#817, #1236, #1194, #794, #797, #1069.
- New: narrowing sinks unguarded num→int CONV across ADD/SUB (fix in
  `lua_patches/fixes/luajit-v2.1-narrow-guarded-sink.patch`); neg-zero
  loop step (= LuaJIT#1432, reported); `tracek()` OOB/SIGSEGV; lost
  HSTORE at `-O3`.
- Size: 266 commits 2022-11..2026-08; 9,711 LOC core translator;
  6,303 LOC fuzzer; 4,669 LOC tests; 99 IR opcodes, 82 dispatched,
  ~76 modelled, 202 typed handlers; MAXSNAP 500.
- Suite: 90 end-to-end chunks × 3 assertions; 61+32 per-instruction
  oracle cases.
- Sweeps: arithmetic seeds 1..5000 → 0 sat; tables 1..1600 → ~99.8%
  unsat; shapes 2166 traces → 25 SAT + 21 LINT, all triaged benign.

### Do NOT cite (stale `CLAUDE.md` claims)

- ~~MemCell has 5 constructors~~ → it has **6** (`nil-val` added).
- ~~memory indexed `[ptr][version][key]`~~ → **`[version][ptr][key]`**.
- ~~`flush_pending` / lazy per-ptr ties~~ → removed; the whole
  version-0 image is tied.
- ~~"u32 arithmetic is NYI"~~ → largely implemented; only DIV/MOD/
  bitwise absent, plus recorder-impossible shapes.
- `results.log` is pre-fix. The corpus sweep to cite is `out.log`
  (625 unsat / 9 sat / 25 timeout) — and re-run it before citing.

---

## 6. TODO before 2026-09-10

Ordered by risk.

- [ ] **Artifact.** Mandatory for a Tool paper — no evaluated artifact,
      no acceptance. Needs Docker: two LuaJIT builds (`af5d38f1`,
      `203a9868~`), cvc5 + z3, the corpus, and the coverage scripts.
      `.dockerignore` already exists; nothing else does.
- [ ] **`cgo` build mode** in `paper/Makefile` — `acmart` sigconf
      instead of `llncs`. Content fits: 11 ACM pages holds more than
      LNCS 16, so this is a reformat, not a rewrite.
- [ ] **Anonymise** for double-blind: author block, and the repo URL in
      the availability paragraph (use anonymous.4open.science or a
      stripped tarball).
- [ ] Close the float-key generator gap (§2) — optional but cheap, and
      it upgrades the subsumption claim.
- [ ] Re-run the `out.log` corpus sweep so the sat/unsat numbers are
      current.
- [ ] Fill the `paper/main.tex` TODOs: affiliation, email, repo URL.

---

## 7. Harvesting the master's thesis

Source: `~/study/diploma/master_diploma`. Russian, LaTeX (GOST template),
67 pages, compiled 2026-06-10. Entry point `thesis/main.tex`; chapters in
`thesis/Dissertation/`. A Beamer defense deck sits in `presentation/`.

Reusing your own thesis is standard and is not prior publication for CGO's
purposes — the rule is about conference/journal papers. Translate and
compress; do not paste.

### Directly reusable (a)

- **Worked end-to-end example, LJ#783** (`x - (-0.0)` wrongly folded to
  `x`): Lua → unoptimized IR → optimized IR → SMT assertions →
  contradiction. A **complete SMT-LIB dump** for it is preserved
  (commented out) at `presentation/main.tex:285-321`. This is the single
  best asset in the thesis — an encoding walkthrough the paper currently
  lacks entirely, already correct, liftable almost verbatim.
- **Soundness / trust argument**: ljopt wraps its own translation and
  emission loop in `jit.off(true,true)`, so the verifier's own Lua never
  executes under the JIT it is checking. Reviewers *will* ask "what if the
  bug corrupts your verifier too" — this answers it in two sentences.
  Currently absent from `main.tex`. Add it to the vacuous-proofs subsection.
- **Scope limitation via LJ#1262**: a stack buffer overflow in
  `narrow_conv_backprop()` under deep recursion. The *trace* is correct, so
  SMT equivalence returns unsat and misses it. Crisp statement of
  crash-bugs-vs-miscompiles, strengthens the limitations section.
- **Solver-selection rationale**: Z3 vs cvc5 vs Bitwuzla vs Yices2 vs
  MathSAT5, with concrete disqualifying reasons per alternative. Good
  design-decision prose for the implementation section.
- **CHC / Horn rejection rationale**: why Spacer is impractical for
  QF_FP + QF_BV + Arrays + Strings, motivating bounded unrolling. Matches
  what we already know; the thesis has it written up with citations.
- **Table: approaches comparison** (testing vs SMT verification vs full
  formal verification, across input-completeness, program-completeness,
  automation, effort, scalability, compiler-modification). Conceptual, not
  numeric — translate and keep.
- **Industrial-deployment bullets**: Tarantool, OpenResty, CryEngine,
  Defold, Snort/Suricata, CERN/NodeMCU. Strengthens the intro's "widely
  deployed" claim, which currently names only three.
- **Bibliography**: `thesis/biblio/cites.bib`, 24 entries. Adds entries
  `refs.bib` lacks and should have: YARPGen (OOPSLA'20), seL4 (SOSP'09),
  CertiKOS (OSDI'16), smtgcc, Spacer (CAV'14), Horn-clause survey, "A
  Survey of Modern Compiler Fuzzing" (arXiv 2306.06884), Cook 1971.
  Cleanup on import: strip stray `language={russian}`, and **verify the
  `pnkfelder2020` entry** — it looks fabricated and is cited nowhere.

### The find worth chasing

**Two bugs found in Z3 itself.** Verified against the Z3 tracker
2026-08-31 — both real, both now **closed**:

- **Z3#9488, "Invalid model was generated"** (filed 2026-05-09). This is
  the soundness one: Z3 produced an invalid model, i.e.\ a false-positive
  `sat`. State the claim precisely as *unsound model*, not "wrong answer".
- **Z3#9234, "Rec fun redefinition assertion failure"** (filed
  2026-04-05). A crash, not a soundness bug. Do not describe it as one.

A translation validator that finds an unsoundness in its own solver is a
strong hook, and it is *not* in `main.tex` or in §5 above. It pairs
naturally with the existing "cvc5 < 1.2.0 answers some formulas
incorrectly" limitation: together they make the point that the oracle's
trust base is itself a moving target, which is why the encoding is kept
portable across two solvers.

Also from the thesis and not in §5: **LJ#1429**, found during development
without SMT.

### Reusable after renumbering (b)

- **Table: IR categories** — 12 categories with per-category instruction
  counts. Structure is good; the headline **76 of 96** is stale (the paper
  says 76 of 82 dispatched, out of 99 opcodes). The defense deck already
  says 78/96, so this number drifted even within the thesis effort. Re-derive.
- **Abstract** (`1_annotation.tex`) — dense and well-structured, maps onto
  an ACM abstract, but every number needs refreshing.
- **Table: regression-bug results** — 17 rows shown of 34 tested. Our
  corpus is now 35 cases; re-derive rather than patch.

### Obsolete (c)

- **Table: corpus performance** (20,000 grammar-fuzzer programs in ~10 min,
  13 timeouts; 122,955 moonsmith programs in ~2 h, ~7% timeouts, on an
  i9-14900HX with a 30 s Z3 timeout). Superseded by §2 — and note our
  corpus arm now runs 120,690 programs in 8 minutes with zero timeouts,
  because it is not invoking the solver at all. Do not mix the two.
- **"40% code coverage"** — stale and weak; §2 replaces it.
- **All figures.** There are none: zero `\includegraphics` and zero TikZ in
  the entire thesis. The closest thing is a three-line ASCII sketch of
  `shared_mem_stack` splitting into `unopt_mem_stack` / `opt_mem_stack`
  (`4_work.tex:628`). Every diagram in the paper must be authored new.
- `ljopt_demo.png` is a Compiler Explorer screenshot, not a designed
  figure. `high_iq.png` is a meme. Neither belongs in an ACM paper.
- The MIPT conference abstract in `conf_thesises/` claims only one bug
  found — superseded.

### From the thesis reviewer's report

The reviewer flagged one real gap: incomplete analysis of applicability to
complex optimizations such as allocation sinking. We already concede
sinking is "covered but not verified" — say so explicitly in limitations
rather than letting a CGO reviewer find it.

The reviewer also suggested revisiting the SMT translation of `RENAME`.
**Do not act on that**, and do not list it as future work: `IR_RENAME` is
emitted only by the register allocator (`lj_asm.c`, in `ra_rename`) and
read back by `lj_snap.c` to restore snapshots. It never appears in the IR
the optimizer produces — it is appended during assembly, below the
abstraction ljopt checks. Modelling it is not a gap we can close, it is
outside the tool's scope by construction, in exactly the same way as
finding (iv), the DCE-off register-allocator clobber on which ljopt
correctly answers `unsat`. If a reviewer raises `RENAME`, that is
the answer.

### Figures the paper needs, and what the thesis gives us to draw them from

No images to reuse, but the descriptive raw material exists:

1. **Pipeline diagram** — the six translator stages (init context → loop
   unrolling → IR-node construction → analysis passes → SMT-LIB generation
   → snapshot construction), from `4_work.tex`.
2. **Dual-compilation / shared-memory architecture** — from the ASCII
   sketch: `shared_mem` tied at version 0 to both `mem_unopt` and
   `mem_opt`.
3. **Coverage bar chart or saturation curve** — from §2. This is the one
   figure that carries the paper's argument, so draw it first.

---

## 8. Idea backlog

Things worth doing that are not on the critical path.

- **Coverage per CPU-hour**, not just coverage. irfuzz reaches 97.5%
  in ~3 minutes; the corpus reaches 37.5% in ~8. Normalising makes the
  gap starker and pre-empts "you gave the baseline less budget".
- **A second target.** The single strongest answer to the generality
  objection would be a partial port to another IR-based JIT. Far too
  large for September; a good journal-extension or follow-up story.
- **Bug-finding power, not just coverage.** Coverage is a proxy. If
  the 35-case historical corpus can be split into "reachable by
  program-level fuzzing" vs "reachable only by IR replay", that
  converts the coverage argument into a bug-detection argument, which
  is strictly stronger. Check how many of the 35 the corpus arm can
  even reach.
- **Mutation score** on the optimizer as a third axis, if there is
  ever time.
