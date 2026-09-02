#!/usr/bin/env bash
# Dump per-commit diff between two equivalent branches (same length,
# same order). Pairs commits by position and writes one diff per pair.
#
# Usage: dump_rebase_diff.sh <old-ref> <new-ref> [base-ref] [out-dir]
#   base-ref defaults to "devel"
#   out-dir  defaults to "./rebase_diffs"

set -euo pipefail

OLD="${1:?need old ref}"
NEW="${2:?need new ref}"
BASE="${3:-devel}"
OUT="${4:-./rebase_diffs}"

mkdir -p "$OUT"

# Oldest-first list of commit SHAs on each side.
mapfile -t OLD_SHAS < <(git rev-list --reverse "$BASE..$OLD")
mapfile -t NEW_SHAS < <(git rev-list --reverse "$BASE..$NEW")

if [ "${#OLD_SHAS[@]}" -ne "${#NEW_SHAS[@]}" ]; then
    echo "commit count differs: old=${#OLD_SHAS[@]} new=${#NEW_SHAS[@]}" >&2
    echo "fall back to: git range-diff $BASE $OLD $NEW" >&2
    exit 1
fi

# Summary index.
INDEX="$OUT/INDEX.txt"
: > "$INDEX"

for i in "${!OLD_SHAS[@]}"; do
    o="${OLD_SHAS[$i]}"
    n="${NEW_SHAS[$i]}"
    subj=$(git log -1 --format='%s' "$n")
    # Sanitize subject for filename.
    safe=$(printf '%s' "$subj" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-80)
    idx=$(printf '%02d' "$((i + 1))")
    f="$OUT/${idx}_${safe}.diff"
    {
        echo "old: $o"
        echo "new: $n"
        echo "subj: $subj"
        echo "--- commit-message diff ---"
        diff -u \
            <(git log -1 --format='%B' "$o") \
            <(git log -1 --format='%B' "$n") \
        || true
        echo "--- tree diff (old -> new) ---"
        git diff "$o" "$n"
    } > "$f"
    printf '%s  %s  %s\n' "$idx" "$o..$n" "$subj" >> "$INDEX"
done

echo "wrote ${#OLD_SHAS[@]} diffs to $OUT"
echo "summary: $INDEX"
