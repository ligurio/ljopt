#!/usr/bin/env bash
# Report line coverage of the six LuaJIT optimizer files from whatever
# .gcda counters are currently in the coverage build.
#
# Two things gcov is picky about here. It must run from the LuaJIT
# source directory, because that is where it resolves the sources. And
# it must be handed the .gcno path explicitly: CMake names its objects
# lj_opt_fold.c.o, so the notes file gcov would infer from a bare
# "lj_opt_fold.c" has the wrong name and it reports no executable
# lines. gcc 11.5 reads the 11.1 notes with a version warning; the
# totals it reports match the published table.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$ROOT/build/luajit_cov/src
OBJ=CMakeFiles/core_static.dir
FILES="lj_opt_fold lj_opt_mem lj_opt_loop lj_opt_dce lj_opt_sink lj_opt_narrow"

cd "$SRC" || exit 1

tot=0; hit=0
for f in $FILES; do
    gcov-11 -o "$OBJ" "$OBJ/$f.c.gcno" >/dev/null 2>&1
    g="$f.c.gcov"
    if [ ! -f "$g" ]; then echo "$f: NO GCOV"; continue; fi
    read -r n h < <(awk -F: '
        { c = $1; gsub(/^ +| +$/, "", c) }
        c == "-" { next }
        { n++ }
        c ~ /^[#=]/ { next }
        { h++ }
        END { print n+0, h+0 }
    ' "$g")
    tot=$((tot+n)); hit=$((hit+h))
    printf '%-18s %5d %5d  %5.1f%%\n' "$f.c" "$n" "$h" \
        "$(awk -v a="$h" -v b="$n" 'BEGIN{print b?100*a/b:0}')"
done
printf '%-18s %5d %5d  %5.1f%%\n' TOTAL "$tot" "$hit" \
    "$(awk -v a="$hit" -v b="$tot" 'BEGIN{print b?100*a/b:0}')"
