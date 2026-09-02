#!/usr/bin/env python3
"""Compare two gcov snapshots of the LuaJIT optimizer line by line.

Each snapshot is a directory of lj_opt_*.c.gcov files, saved off after
one arm of the comparison has run (see scripts/cov_corpus.sh and
scripts/cov_irfuzz.sh). Reports what each arm reaches alone, what only
one of them reaches, and what neither does.

    scripts/cov_compare.py <corpus-snapshot-dir> <irfuzz-snapshot-dir>
"""
import sys

FILES = ["lj_opt_fold", "lj_opt_mem", "lj_opt_loop",
         "lj_opt_dce", "lj_opt_sink", "lj_opt_narrow"]


def parse(path):
    """Return (executable lines, hit lines) as sets of line numbers."""
    executable, hit = set(), set()
    with open(path, errors="replace") as f:
        for raw in f:
            parts = raw.split(":", 2)
            if len(parts) < 3:
                continue
            count, lineno = parts[0].strip(), parts[1].strip()
            if count == "-" or not lineno.isdigit():
                continue
            n = int(lineno)
            if n == 0:
                continue
            executable.add(n)
            # gcov marks an unexecuted line '#####', or '=====' when it
            # is unreachable in the flow graph.
            if count[0] not in "#=":
                hit.add(n)
    return executable, hit


def main(corpus_dir, irfuzz_dir):
    print(f"{'file':<18}{'lines':>6}{'corpus':>8}{'irfuzz':>8}"
          f"{'only-c':>8}{'only-i':>8}{'union':>7}{'neither':>8}")
    total = dict(ex=0, c=0, i=0, oc=0, oi=0, u=0)
    for f in FILES:
        ex_c, hit_c = parse(f"{corpus_dir}/{f}.c.gcov")
        ex_i, hit_i = parse(f"{irfuzz_dir}/{f}.c.gcov")
        if ex_c != ex_i:
            sys.exit(f"{f}: snapshots disagree on which lines are "
                     f"executable -- they came from different builds"
            )
        only_c, only_i = hit_c - hit_i, hit_i - hit_c
        union = hit_c | hit_i
        print(f"{f + '.c':<18}{len(ex_c):>6}{len(hit_c):>8}{len(hit_i):>8}"
              f"{len(only_c):>8}{len(only_i):>8}{len(union):>7}"
              f"{len(ex_c) - len(union):>8}")
        if only_c:
            print(f"    reached only by the corpus: {sorted(only_c)}")
        total["ex"] += len(ex_c)
        total["c"] += len(hit_c)
        total["i"] += len(hit_i)
        total["oc"] += len(only_c)
        total["oi"] += len(only_i)
        total["u"] += len(union)
    print(f"{'TOTAL':<18}{total['ex']:>6}{total['c']:>8}{total['i']:>8}"
          f"{total['oc']:>8}{total['oi']:>8}{total['u']:>7}"
          f"{total['ex'] - total['u']:>8}")
    ex = total["ex"]
    print(f"\ncorpus {100.0 * total['c'] / ex:.1f}%   "
          f"irfuzz {100.0 * total['i'] / ex:.1f}%   "
          f"union {100.0 * total['u'] / ex:.1f}%")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
