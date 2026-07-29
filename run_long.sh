#!/bin/sh
# Long-running IR fuzz. Defaults to z3; LJOPT_SOLVER=cvc5 to compare.
# The two are close on these formulas -- see the note in fuzz.lua.
cd /home/alexey-churkin/study/diploma/ljopt-fuzz-cvc5
export LUA_PATH="./?/init.lua;;"
export PATH="$PWD/build/luajit_af5d38f109b6a7f714b41f92a57e2bd67d14955a/src:$PATH"
export LD_LIBRARY_PATH=../z3/build
export LJOPT_Z3_TIMEOUT=${LJOPT_Z3_TIMEOUT:-60}
export LJOPT_SOLVER=${LJOPT_SOLVER:-z3}
export LJOPT_CVC5_BIN=../cvc5/build/bin/cvc5
export LJOPT_Z3_BIN=../z3/build/z3
COUNT=${COUNT:-1000}
# Random starting seed each launch (override with: BASE=12345 ./run_cvc5.sh).
BASE=${BASE:-$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')}
echo "solver: $LJOPT_SOLVER  seed base: $BASE  count/worker: $COUNT"
echo "rerun this range with: BASE=$BASE COUNT=$COUNT ./run_long.sh"
seq 0 15 | xargs -P16 -I{} sh -c "luajit ljopt/irfuzz/fuzz.lua --tables --insns 20 --seed \$(($BASE + {}*$COUNT)) --count $COUNT"
