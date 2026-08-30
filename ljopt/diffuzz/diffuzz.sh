#!/bin/bash
# Differential-test one generated program: interpreter vs several JIT
# configurations. Prints nothing when they agree.
#
#   LJ=<luajit> ./diffuzz.sh <seed> [workdir]
set -u
LJ="${LJ:-luajit}"
here=$(cd "$(dirname "$0")" && pwd)
seed="$1"
work="${2:-${TMPDIR:-/tmp}}"
p="$work/diffuzz_$seed.lua"

CONFIGS=("-O3" "-O2" "-O1" "-Ohotloop=1" "-Ohotloop=1,hotexit=1"
         "-O3,hotloop=2,hotexit=2" "-Ohotloop=1,-fold" "-Ohotloop=1,-narrow"
         "-Ohotloop=1,-loop" "-Ohotloop=1,-fwd" "-Ohotloop=1,-dse"
         "-Ohotloop=1,-abc" "-Ohotloop=1,-sink" "-Ohotloop=1,-cse"
         "-O3,-dce" "-O3,-fwd")
TIMEOUT="${LJOPT_DIFFUZZ_TIMEOUT:-90}"

run() { timeout "$TIMEOUT" nice -n 19 "$LJ" $1 "$p" 2>&1; echo "rc=$?"; }

timeout "$TIMEOUT" nice -n 19 "$LJ" "$here/gen.lua" "$seed" > "$p" 2>/dev/null \
  || { rm -f "$p"; exit 0; }

a=$(run "-joff")
case "$a" in *"rc=124"*|*"rc=1"*) rm -f "$p"; exit 0;; esac

for o in "${CONFIGS[@]}"; do
  b=$(run "$o")
  case "$b" in *"rc=124"*) continue;; esac
  [ "$a" = "$b" ] && continue
  a2=$(timeout $((TIMEOUT * 2)) nice -n 19 "$LJ" -joff "$p" 2>&1)
  b2=$(timeout $((TIMEOUT * 2)) nice -n 19 "$LJ" $o "$p" 2>&1)
  if [ -n "$a2" ] && [ "$a2" != "$b2" ]; then
    echo "=== MISMATCH seed=$seed [$o] prog=$p"
    echo "  interp: $(printf '%s' "$a2" | head -1)"
    echo "  jit   : $(printf '%s' "$b2" | head -1)"
  fi
  exit 0
done
rm -f "$p"
