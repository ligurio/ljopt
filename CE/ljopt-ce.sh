#!/bin/bash
# Wrapper for Compiler Explorer: ljopt (Lua -> SMT-LIB) | z3
# Compilation mode: ljopt-ce.sh [-S] [-g] -o <outputfile> <input.lua>
# Execution mode:   ljopt-ce.sh <input.lua>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUAJIT="$SCRIPT_DIR/build/luajit_af5d38f109b6a7f714b41f92a57e2bd67d14955a/src/luajit"
LUA_PATH="$SCRIPT_DIR/?/init.lua;$SCRIPT_DIR/?.lua;$(luarocks path --lr-path 2>/dev/null);;"
export LUA_PATH

OUTPUT_FILE=""
INPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -S|-g) shift ;;
        *) INPUT_FILE="$1"; shift ;;
    esac
done

if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: ljopt-ce.sh [-S] [-g] [-o <output>] <input.lua>" >&2
    exit 1
fi

SMT_OUTPUT=$("$LUAJIT" "$SCRIPT_DIR/bin/ljopt" "$INPUT_FILE" 2>&1)
LJOPT_EXIT=$?

if [[ $LJOPT_EXIT -ne 0 ]]; then
    echo "$SMT_OUTPUT" >&2
    exit $LJOPT_EXIT
fi

if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$SMT_OUTPUT" > "$OUTPUT_FILE"
else
    echo "$SMT_OUTPUT" | z3 -in 2>&1
fi
