#!/usr/bin/env bash
# Baseline arm of the coverage comparison: drive moonsmith corpus
# programs through the gcov-instrumented LuaJIT with the JIT on, so the
# counters show what *program-level* fuzzing reaches in lj_opt_*.c.
#
# One process per file: gcov merges counters across process exits, so a
# hang or a crash costs one file rather than the whole run. Hot
# thresholds are lowered to 3 so that short generated programs still
# compile traces -- this is deliberately generous to the baseline.
#
#   scripts/cov_corpus.sh <first> <last> [corpus-list]
#
# The list defaults to build/cov/corpus.list; regenerate it with
#   find <corpus> -name '*.lua' | sort | shuf --random-source=<(yes 42)
# Counters accumulate, so call this repeatedly with adjacent ranges to
# get a saturation curve, reporting with scripts/cov_report.sh between
# stages.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LJ=$ROOT/build/luajit_cov/src/luajit
LIST=${3:-$ROOT/build/cov/corpus.list}
WORK=$ROOT/build/cov/work

first=$1
last=$2

[ -x "$LJ" ] || { echo "no coverage build at $LJ" >&2; exit 1; }
[ -f "$LIST" ] || { echo "no corpus list at $LIST" >&2; exit 1; }

mkdir -p "$WORK"
cd "$WORK" || exit 1

ok=0; fail=0; to=0
while IFS= read -r f; do
    timeout 5 "$LJ" -O3 -Ohotloop=3 -Ohotexit=3 -Otryside=3 "$f" \
        >/dev/null 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then ok=$((ok+1))
    elif [ $rc -eq 124 ]; then to=$((to+1))
    else fail=$((fail+1))
    fi
done < <(sed -n "${first},${last}p" "$LIST")

echo "ran=$((ok+fail+to)) ok=$ok err=$fail timeout=$to"
