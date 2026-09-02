#!/usr/bin/env python3
"""Time an SMT solver over a fixed set of ljopt queries.

Runs sequentially and one query at a time: the point is per-query wall
latency, and running them in parallel would measure contention instead.
Both solvers get byte-identical inputs so the two are comparable.

    scripts/bench_solver.py <cvc5|z3> <query-dir> [timeout-sec]

Reports the verdict breakdown and the latency distribution, and writes a
<solver>.csv of (query, verdict, seconds) next to the queries so a plot or
a second pass does not have to re-run anything.
"""
import os
import subprocess
import sys
import time

CVC5 = os.environ.get("LJOPT_CVC5_BIN", "../cvc5/build/bin/cvc5")
Z3 = os.environ.get("LJOPT_Z3_BIN", "../z3/build/z3")


def command(solver, path, timeout):
    if solver == "z3":
        return [Z3, f"-T:{timeout}", path]
    # --arrays-exp is required for the constant arrays the memory
    # encoding builds on. --tlimit-per, not --tlimit: the latter aborts
    # the process with no verdict (and dumps core), which reads as a
    # solver error rather than a timeout.
    return [CVC5, "--arrays-exp", f"--tlimit-per={timeout * 1000}", path]


def verdict_of(stdout):
    # Match a verdict line exactly rather than searching the whole
    # output: an error mentioning "unsatisfiable" would otherwise read
    # as a verdict. Same discipline as irfuzz/fuzz.lua.
    for line in stdout.splitlines():
        line = line.strip()
        if line == "unsat":
            return "unsat"
        if line == "sat":
            return "sat"
        if line == "timeout" or line.startswith("unknown"):
            return "unknown"
    return "error"


def percentile(values, q):
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(int(q * len(ordered)), len(ordered) - 1)
    return ordered[idx]


def main(solver, qdir, timeout):
    queries = sorted(f for f in os.listdir(qdir) if f.endswith(".smt2"))
    if not queries:
        sys.exit(f"no .smt2 files in {qdir}")

    env = dict(os.environ)
    # The local z3 build needs its own libs; harmless for cvc5.
    env["LD_LIBRARY_PATH"] = (
        "../z3/build:" + env.get("LD_LIBRARY_PATH", "")
    )

    rows, counts = [], {}
    for i, q in enumerate(queries, 1):
        path = os.path.join(qdir, q)
        start = time.perf_counter()
        try:
            proc = subprocess.run(
                command(solver, path, timeout),
                capture_output=True, text=True, env=env,
                # A solver that ignores its own limit must not wedge the
                # run; give it a generous grace period over the limit.
                timeout=timeout + 30,
            )
            out = proc.stdout
        except subprocess.TimeoutExpired:
            out = "timeout"
        elapsed = time.perf_counter() - start
        v = verdict_of(out)
        counts[v] = counts.get(v, 0) + 1
        rows.append((q, v, elapsed))
        if i % 25 == 0:
            print(f"  {i}/{len(queries)}", file=sys.stderr, flush=True)

    csv = os.path.join(qdir, f"{solver}.csv")
    with open(csv, "w") as fh:
        fh.write("query,verdict,seconds\n")
        for q, v, s in rows:
            fh.write(f"{q},{v},{s:.3f}\n")

    times = [s for _, _, s in rows]
    closed = [s for _, v, s in rows if v in ("sat", "unsat")]
    total = sum(times)
    print(f"\n{solver}: {len(rows)} queries, {timeout}s limit")
    for v in sorted(counts):
        print(f"  {v:<8} {counts[v]:>5}")
    print(f"  closed   {len(closed):>5} of {len(rows)} "
          f"({100.0 * len(closed) / len(rows):.1f}%)")
    print(f"  total    {total:>8.1f}s  ({total / 60:.1f} min)")
    print(f"  mean     {total / len(times):>8.2f}s")
    print(f"  median   {percentile(times, 0.50):>8.2f}s")
    print(f"  p90      {percentile(times, 0.90):>8.2f}s")
    print(f"  p99      {percentile(times, 0.99):>8.2f}s")
    print(f"  max      {max(times):>8.2f}s")
    if closed:
        print(f"  median (closed only) {percentile(closed, 0.50):.2f}s")
    print(f"  csv -> {csv}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2],
         int(sys.argv[3]) if len(sys.argv) > 3 else 30)
