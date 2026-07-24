#!/bin/sh
cd /home/alexey-churkin/study/diploma/ljopt
export LUA_PATH="./?/init.lua;;"
export PATH="$PWD/build/luajit_af5d38f109b6a7f714b41f92a57e2bd67d14955a/src:$PATH"
export LD_LIBRARY_PATH=../z3/build
export LJOPT_Z3_TIMEOUT=60
export LJOPT_Z3_BIN=../z3/build/z3
# Random starting seed each launch (override with: BASE=12345 ./run.sh).
BASE=${BASE:-$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')}
echo "seed base: $BASE  (rerun this range with: BASE=$BASE ./run.sh)"
seq 0 15 | xargs -P16 -I{} sh -c "luajit ljopt/irfuzz/fuzz.lua --tables --insns 20 --seed \$(($BASE + {}*50)) --count 50"
