#!/usr/bin/env bash
# Differential solver testing over ljopt queries: run cvc5 and z3 on
# byte-identical formulas and look for answers that cannot both be right.
#
#   scripts/diff_solvers.sh <query-dir> [jobs] [timeout-sec]
#
# A sat/unsat disagreement is definitive: the formula has a model or it
# does not, so one solver is unsound. One side answering `unknown` is not
# a bug, only a difference in strength.
#
# Both solvers also self-validate any model they produce -- cvc5 with
# --check-models, z3 with model_validate=true -- so a solver that answers
# sat on a formula it cannot actually satisfy reports itself. That is the
# shape of both known findings: cvc5 1.1.2's fp.to_sbv unsoundness and
# Z3#9488.
#
# Verdicts only, so this parallelises freely: contention cannot change a
# sat/unsat answer, only how long it takes to arrive.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QDIR=${1:?usage: diff_solvers.sh <query-dir> [jobs] [timeout-sec]}
JOBS=${2:-8}
TIMEOUT=${3:-20}

CVC5=${LJOPT_CVC5_BIN:-$ROOT/../cvc5/build/bin/cvc5}
Z3=${LJOPT_Z3_BIN:-$ROOT/../z3/build/z3}

verdict_of() {
    # Match a verdict line exactly: an error mentioning "unsatisfiable"
    # would otherwise read as a verdict.
    local out=$1 v=error
    while IFS= read -r line; do
        case $line in
            unsat) v=unsat; break ;;
            sat) v=sat; break ;;
            unknown*|timeout) v=unknown; break ;;
        esac
    done <<< "$out"
    printf '%s' "$v"
}

badness_of() {
    case $1 in
        *"ERRORS SATISFYING ASSERTIONS"*|*"model unsound"*|\
        *"Invalid model"*|*"invalid model"*|*"model is not"*) \
            printf 'BAD_MODEL' ;;
        *"internal error"*|*"Internal error"*|*"Fatal failure"*|\
        *"ASSERTION VIOLATION"*) printf 'INTERNAL' ;;
        *) printf '' ;;
    esac
}

run_pair() {
    local q=$1 cvc5=$2 z3=$3 t=$4 root=$5
    local co zo cv zv cb zb note rc_c rc_z

    co=$(timeout $((t + 30)) "$cvc5" --arrays-exp --tlimit-per=$((t * 1000)) \
            --check-models "$q" 2>&1); rc_c=$?
    zo=$(LD_LIBRARY_PATH="$root/../z3/build" timeout $((t + 30)) \
            "$z3" -T:"$t" model_validate=true "$q" 2>&1); rc_z=$?

    cv=$(verdict_of "$co"); zv=$(verdict_of "$zo")
    cb=$(badness_of "$co");  zb=$(badness_of "$zo")
    [ $rc_c -ge 128 ] && cb="${cb:+$cb/}SIG$rc_c"
    [ $rc_z -ge 128 ] && zb="${zb:+$zb/}SIG$rc_z"

    note=agree
    if [ "$cv" != "$zv" ]; then
        case "$cv/$zv" in
            sat/unsat|unsat/sat) note=DISAGREE ;;
            *) note=differ_strength ;;
        esac
    fi
    [ -n "$cb$zb" ] && note="${note}+SELFCHECK"

    printf '%s,%s,%s,%s,%s,%s\n' \
        "$(basename "$q")" "$cv" "$zv" "${cb:-}" "${zb:-}" "$note"
}
export -f run_pair verdict_of badness_of

echo "query,cvc5,z3,cvc5_flag,z3_flag,note"
find "$QDIR" -name '*.smt2' | sort | \
    xargs -P "$JOBS" -I{} bash -c \
        "run_pair {} '$CVC5' '$Z3' $TIMEOUT '$ROOT'" 2>/dev/null
