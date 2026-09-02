#!/usr/bin/env bash
# IR-replay arm of the coverage comparison: every covrun.lua mode, with
# and without COV_LOOP, capped at 8000 traces. This is the sweep
# ljopt/irfuzz/README.md reports as 2449/2513 lines.
#
# One process per mode, as the README prescribes: gcov merges counters
# across process exits, so a crash in one mode keeps the coverage of
# the others. COV_JITOFF stops the host JIT compiling ljopt's own Lua
# and polluting the counters; covrun.lua ignores it for the `recorded`
# mode, which needs the JIT left on.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LJ=$ROOT/build/luajit_cov/src/luajit
LIMIT=${1:-8000}

MODES="random tables gaps mixed alias strings xmem guard narrow sink
       buffers abc upval ahref strops bufcalls shapes xref licm recorded
       int1 int2 num1 num2 i641 i642"

[ -x "$LJ" ] || { echo "no coverage build at $LJ" >&2; exit 1; }

cd "$ROOT" || exit 1

for loop in 0 1; do
    for m in $MODES; do
        start=$(date +%s)
        if [ "$loop" = 1 ]; then
            COV_LOOP=1 COV_JITOFF=1 LUA_PATH="./?/init.lua;;" \
                timeout 600 "$LJ" ljopt/irfuzz/covrun.lua "$m" "$LIMIT" \
                >/dev/null 2>&1
        else
            COV_JITOFF=1 LUA_PATH="./?/init.lua;;" \
                timeout 600 "$LJ" ljopt/irfuzz/covrun.lua "$m" "$LIMIT" \
                >/dev/null 2>&1
        fi
        printf 'loop=%s %-10s rc=%d %ds\n' \
            "$loop" "$m" "$?" "$(( $(date +%s) - start ))"
    done
done
