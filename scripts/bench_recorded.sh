#!/usr/bin/env bash
# End-to-end verification cost for real Lua programs, split into its two
# components: translation (record the chunk twice, emit SMT-LIB) and
# solving (discharge the emitted formula).
#
#   scripts/bench_recorded.sh <first> <last> [corpus-list] [timeout-sec]
#
# Emits one CSV row per program: file, smt bytes, translate seconds,
# solve seconds, verdict. A program that records no trace pair produces
# no formula and is reported as verdict "notrace" -- those are not
# verification work and must be excluded before averaging.
#
# Sequential on purpose: these are latency numbers, and running the
# programs in parallel would measure contention instead.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LJ=${LJOPT_LUA_BIN:-$ROOT/build/luajit_af5d38f109b6a7f714b41f92a57e2bd67d14955a/src/luajit}
CVC5=${LJOPT_CVC5_BIN:-$ROOT/../cvc5/build/bin/cvc5}
LIST=${3:-$ROOT/build/cov/corpus.list}
TIMEOUT=${4:-30}

first=$1
last=$2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "file,smt_bytes,translate_s,solve_s,verdict"
while IFS= read -r f; do
    smt=$tmp/q.smt2

    t0=$(date +%s.%N)
    LUA_PATH="$ROOT/?/init.lua;;" timeout 120 "$LJ" "$ROOT/ljopt/main.lua" \
        "$f" > "$smt" 2>/dev/null
    t1=$(date +%s.%N)
    translate=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b-a}')

    bytes=$(stat -c %s "$smt" 2>/dev/null || echo 0)
    # No check-sat means no trace pair was recorded: nothing to verify.
    if [ "$bytes" -lt 64 ] || ! grep -q 'check-sat' "$smt" 2>/dev/null; then
        printf '%s,%s,%s,,notrace\n' "$(basename "$f")" "$bytes" "$translate"
        continue
    fi

    s0=$(date +%s.%N)
    out=$(LD_LIBRARY_PATH="$ROOT/../z3/build" timeout $((TIMEOUT + 30)) \
        "$CVC5" --arrays-exp --tlimit-per=$((TIMEOUT * 1000)) "$smt" \
        2>/dev/null)
    s1=$(date +%s.%N)
    solve=$(awk -v a="$s0" -v b="$s1" 'BEGIN{printf "%.3f", b-a}')

    # Match a verdict line exactly: an error mentioning "unsatisfiable"
    # would otherwise read as a verdict.
    verdict=error
    while IFS= read -r line; do
        case $line in
            unsat) verdict=unsat; break ;;
            sat) verdict=sat; break ;;
            unknown*|timeout) verdict=unknown; break ;;
        esac
    done <<< "$out"

    printf '%s,%s,%s,%s,%s\n' \
        "$(basename "$f")" "$bytes" "$translate" "$solve" "$verdict"
done < <(sed -n "${first},${last}p" "$LIST")
