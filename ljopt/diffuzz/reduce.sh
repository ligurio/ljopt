#!/bin/bash
# Shrink a diverging program by deleting lines while the divergence
# survives.
#
#   LJ=<luajit> ./reduce.sh <prog.lua> <jit-flags> <out.lua>
set -u
LJ="${LJ:-luajit}"
prog="$1"; OPT="$2"; OUT="$3"
work=$(mktemp "${TMPDIR:-/tmp}/reduce.XXXXXX.lua")
trap 'rm -f "$work"' EXIT

diverges() {
  cp "$1" "$work"
  local a b
  a=$(timeout 30 nice -n 19 "$LJ" -joff "$work" 2>&1) || return 1
  case "$a" in *"lua:"*|"") return 1;; esac
  b=$(timeout 30 nice -n 19 "$LJ" $OPT "$work" 2>&1) || return 1
  case "$b" in *"lua:"*|"") return 1;; esac
  [ "$a" != "$b" ]
}

cp "$prog" "$OUT"
diverges "$OUT" || { echo "does not reproduce under $OPT" >&2; exit 1; }

n0=$(wc -l < "$OUT")
changed=1
while [ $changed -eq 1 ]; do
  changed=0
  i=1
  while [ $i -le "$(wc -l < "$OUT")" ]; do
    c=$(mktemp "${TMPDIR:-/tmp}/reduce.XXXXXX.lua")
    sed "${i}d" "$OUT" > "$c"
    if diverges "$c"; then mv "$c" "$OUT"; changed=1
    else rm -f "$c"; i=$((i + 1)); fi
  done
done
echo "reduced $n0 -> $(wc -l < "$OUT") lines: $OUT"
