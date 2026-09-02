#!/usr/bin/env bash
# Differential + self-check hunt for SMT solver bugs, over a directory of
# ljopt queries.
#
#   scripts/hunt_solver_bugs.sh <query-dir> <cvc5-binary> [jobs] [timeout]
#
# Verdicts only, so this parallelises freely -- unlike the latency
# benchmark, contention cannot corrupt a sat/unsat answer.
#
# Every query runs with --check-models, so a solver that answers `sat`
# and then rejects the model it just produced reports itself. That is
# exactly the shape of the cvc5 1.1.2 unsoundness recorded in
# tests/smtlib2_cvc5.lua and of Z3#9488.
#
# Output is one CSV row per query; compare two runs to find verdict
# disagreements, which are soundness bugs in whichever solver is wrong.
set -u

QDIR=${1:?usage: hunt_solver_bugs.sh <query-dir> <cvc5-binary> [jobs] [timeout]}
BIN=${2:?need a cvc5 binary}
JOBS=${3:-6}
TIMEOUT=${4:-30}

run_one() {
    local q=$1 bin=$2 timeout_s=$3
    local out rc verdict flag
    out=$(timeout $((timeout_s + 30)) "$bin" --arrays-exp \
            --tlimit-per=$((timeout_s * 1000)) --check-models "$q" 2>&1)
    rc=$?

    verdict=error
    while IFS= read -r line; do
        case $line in
            unsat) verdict=unsat; break ;;
            sat) verdict=sat; break ;;
            unknown*|timeout) verdict=unknown; break ;;
        esac
    done <<< "$out"

    # Anything cvc5 says about its own model, an internal error, or a
    # crash is the interesting part. Keep it on one CSV field.
    flag=
    case $out in
        *"model unsound"*|*"Model is not sound"*|*"invalid model"*) \
            flag=BAD_MODEL ;;
        *"Cannot check model"*) flag=model_uncheckable ;;
        *"internal error"*|*"Internal error"*|*"Assertion"*|*"assertion"*) \
            flag=INTERNAL ;;
        *"unexpected"*|*"Unexpected"*) flag=unexpected ;;
    esac
    [ $rc -ge 128 ] && flag="${flag:+$flag/}SIGNAL_$rc"

    printf '%s,%s,%s,%s\n' "$(basename "$q")" "$verdict" "$rc" "${flag:-}"
}
export -f run_one

echo "query,verdict,rc,flag"
find "$QDIR" -name '*.smt2' | sort | \
    xargs -P "$JOBS" -I{} bash -c \
        "run_one {} '$BIN' $TIMEOUT" 2>/dev/null
