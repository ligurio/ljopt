#!/bin/bash
# Sweep a seed range in parallel.
#
#   LJ=<luajit> ./run.sh <first> <last> [jobs] [workdir]
set -u
here=$(cd "$(dirname "$0")" && pwd)
first="$1"; last="$2"; jobs="${3:-4}"; work="${4:-${TMPDIR:-/tmp}}"
mkdir -p "$work"
export LJ="${LJ:-luajit}"
seq "$first" "$last" \
  | nice -n 19 xargs -P "$jobs" -I{} "$here/diffuzz.sh" {} "$work"
