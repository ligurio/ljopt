#!/usr/bin/env python3
"""
Parse luacov.stats.out and find functions with zero coverage in ljopt/ source files.
"""

import re
import os

STATS_FILE = "/home/alexey-churkin/study/diploma/ljopt/luacov.stats.out"
BASE_DIR = "/home/alexey-churkin/study/diploma/ljopt"

# Regex to detect function definitions
FUNC_RE = re.compile(
    r"""
    ^\s*                           # optional leading whitespace
    (?:local\s+)?                  # optional 'local'
    function\s+                    # 'function' keyword
    ([\w.:]+)                      # function name (may include : or .)
    \s*\(                          # opening paren
    """,
    re.VERBOSE,
)

# Also match method-style: foo.bar = function(...) or foo.bar = local function
ASSIGN_FUNC_RE = re.compile(
    r"""
    ^\s*
    ([\w.:]+)                      # lhs name
    \s*=\s*
    (?:local\s+)?
    function\s*\(
    """,
    re.VERBOSE,
)


def parse_stats(stats_file):
    """Parse luacov.stats.out and return dict: filepath -> {line_num: hit_count}"""
    results = {}
    with open(stats_file, "r") as f:
        lines = f.readlines()

    i = 0
    while i < len(lines):
        header = lines[i].strip()
        i += 1
        if not header:
            continue
        # header format: <max_line>:<filepath>
        m = re.match(r'^(\d+):(.+)$', header)
        if not m:
            continue
        max_line = int(m.group(1))
        filepath = m.group(2).strip()

        if i >= len(lines):
            break
        counts_line = lines[i].strip()
        i += 1

        counts = counts_line.split()
        hit_dict = {}
        for idx, c in enumerate(counts):
            line_num = idx + 1
            hit_dict[line_num] = int(c)

        results[filepath] = hit_dict

    return results


def resolve_path(filepath, base_dir):
    """Resolve a relative or absolute filepath against base_dir."""
    if os.path.isabs(filepath):
        return filepath
    # strip leading './'
    clean = filepath.lstrip("./")
    return os.path.join(base_dir, clean)


def is_ljopt_file(filepath):
    """Check if the filepath is in ljopt/ (not build/, luajit/, tests/)."""
    norm = filepath.replace("\\", "/")
    # Must contain 'ljopt/' but not in excluded dirs
    excluded = ["/build/", "/luajit/", "/tests/", "luajit/", "build/"]
    # Accept paths like ./ljopt/... or ljopt/...
    if "ljopt/" not in norm and not norm.startswith("ljopt/"):
        # check if it ends with ljopt source
        return False
    for excl in excluded:
        if excl in norm:
            return False
    return True


def extract_functions(source_lines):
    """
    Return list of (line_num, func_name) for each function definition found.
    Line numbers are 1-based.
    """
    funcs = []
    for i, line in enumerate(source_lines):
        line_num = i + 1
        m = FUNC_RE.match(line)
        if m:
            funcs.append((line_num, m.group(1)))
            continue
        m2 = ASSIGN_FUNC_RE.match(line)
        if m2:
            funcs.append((line_num, m2.group(1)))
    return funcs


def check_coverage(funcs, hit_dict, total_lines):
    """
    For each function, check if any line from its definition to the next function
    (or end of file) has a hit count > 0.
    Returns list of (line_num, func_name) for untested functions.
    """
    untested = []
    for idx, (line_num, func_name) in enumerate(funcs):
        # Next boundary: next function's line or end of file
        if idx + 1 < len(funcs):
            next_line = funcs[idx + 1][0]
        else:
            next_line = total_lines + 1

        # Check if any line in [line_num, next_line) was hit
        any_hit = False
        for ln in range(line_num, next_line):
            if hit_dict.get(ln, 0) > 0:
                any_hit = True
                break

        if not any_hit:
            untested.append((line_num, func_name))

    return untested


def main():
    print(f"Parsing stats file: {STATS_FILE}")
    stats = parse_stats(STATS_FILE)
    print(f"Total entries in stats: {len(stats)}")

    ljopt_entries = {k: v for k, v in stats.items() if is_ljopt_file(k)}
    print(f"ljopt/ entries: {len(ljopt_entries)}")
    print()

    all_untested = []

    for filepath, hit_dict in sorted(ljopt_entries.items()):
        abs_path = resolve_path(filepath, BASE_DIR)
        if not os.path.exists(abs_path):
            print(f"  [WARN] File not found: {abs_path}")
            continue

        with open(abs_path, "r") as f:
            source_lines = f.readlines()

        total_lines = len(source_lines)
        funcs = extract_functions(source_lines)

        if not funcs:
            continue

        untested = check_coverage(funcs, hit_dict, total_lines)

        for line_num, func_name in untested:
            # Use a clean relative path for display
            rel = os.path.relpath(abs_path, BASE_DIR)
            all_untested.append((rel, line_num, func_name))

    print("=" * 70)
    print("UNTESTED FUNCTIONS (zero coverage)")
    print("=" * 70)
    for rel, line_num, func_name in all_untested:
        print(f"{rel}:{line_num} - {func_name} - UNTESTED")

    print()
    print(f"Total untested functions: {len(all_untested)}")

    # Also print a summary by file
    print()
    print("=" * 70)
    print("SUMMARY BY FILE")
    print("=" * 70)
    from collections import defaultdict
    by_file = defaultdict(list)
    for rel, line_num, func_name in all_untested:
        by_file[rel].append((line_num, func_name))
    for rel in sorted(by_file):
        print(f"\n{rel} ({len(by_file[rel])} untested):")
        for line_num, func_name in by_file[rel]:
            print(f"  line {line_num:4d}: {func_name}")


if __name__ == "__main__":
    main()
