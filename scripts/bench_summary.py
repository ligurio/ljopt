#!/usr/bin/env python3
"""Summarise a scripts/bench_recorded.sh CSV.

    scripts/bench_summary.py <recorded.csv>

Programs that recorded no trace pair ("notrace") are counted but kept out
of every latency figure: no formula was emitted, so they are not
verification work and averaging them in would understate the real cost.
"""
import csv
import sys


def percentile(values, q):
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(int(q * len(ordered)), len(ordered) - 1)]


def describe(name, values, unit="s"):
    if not values:
        print(f"  {name:<22} (none)")
        return
    print(f"  {name:<22} median {percentile(values, 0.50):7.3f}{unit}  "
          f"mean {sum(values) / len(values):7.3f}{unit}  "
          f"p90 {percentile(values, 0.90):7.3f}{unit}  "
          f"max {max(values):7.3f}{unit}")


def main(path):
    rows = list(csv.DictReader(open(path)))
    if not rows:
        sys.exit("empty CSV")

    verdicts = {}
    for r in rows:
        verdicts[r["verdict"]] = verdicts.get(r["verdict"], 0) + 1

    verified = [r for r in rows if r["verdict"] != "notrace"]
    translate = [float(r["translate_s"]) for r in verified]
    solve = [float(r["solve_s"]) for r in verified if r["solve_s"]]
    total = [float(r["translate_s"]) + float(r["solve_s"])
             for r in verified if r["solve_s"]]
    smt = [int(r["smt_bytes"]) for r in verified]

    print(f"{len(rows)} programs, {len(verified)} produced a trace pair")
    for v in sorted(verdicts):
        share = 100.0 * verdicts[v] / len(rows)
        print(f"  {v:<9} {verdicts[v]:>5}  ({share:4.1f}% of all programs)")
    if verified:
        closed = verdicts.get("unsat", 0) + verdicts.get("sat", 0)
        print(f"  closed    {closed:>5}  "
              f"({100.0 * closed / len(verified):4.1f}% of trace pairs)")

    print("\nlatency, per program that produced a trace pair")
    describe("translate", translate)
    describe("solve", solve)
    describe("translate + solve", total)
    describe("SMT size", [b / 1024.0 for b in smt], unit="K")

    if translate and solve:
        print(f"\n  solving is {sum(solve) / sum(translate):.0f}x the cost "
              f"of translation in aggregate")
        print(f"  total wall for {len(verified)} trace pairs: "
              f"{sum(total) / 60:.1f} min")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
