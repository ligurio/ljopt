#!/usr/bin/env python3
"""
Rewrite references to the `package` global in a Lua source
file. Two modes:

  prepend  (default)  Inject `package = {}` at the top so all
                      subsequent reads see an empty table.
                      Source body untouched. Fast, safe.

  replace             Replace every bare `package` identifier
                      with the replacement expression (default
                      `({})`). Skips occurrences inside string
                      literals and comments.

Why: SMT-side, walking `_G.math.__index.package` produces
extra symbolic tab-vals whose ids aren't pinned by the
globals-normalize pass, leaving aliasing freedom for the
solver. Removing the `package` reference in input Lua
sidesteps the chain.

Usage:
    rewrite_package.py file.lua                  # prepend mode
    rewrite_package.py -m replace file.lua
    rewrite_package.py -m replace -r 'nil' f.lua
    rewrite_package.py -o out.lua file.lua       # write to out
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


# Match a bare identifier `package` not preceded/followed by
# identifier chars and not after a `.` or `:` (so `t.package`
# field accesses stay untouched — change to remove that
# guard if you want them rewritten too).
_BARE_PACKAGE_RE = re.compile(r'(?<![\w.:])package(?!\w)')


def _strip_lua_strings_and_comments(src: str):
    """
    Yield (kind, text) chunks where kind is 'code', 'string',
    or 'comment'. We only rewrite inside 'code'. Long-bracket
    strings/comments (`[[...]]`, `--[[...]]`) supported with
    equals-sign levels.
    """
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        # Long comment / long string opener.
        if c == '-' and src.startswith('--', i):
            # `--[[`, `--[=[`, ... long comment.
            j = i + 2
            if j < n and src[j] == '[':
                k = j + 1
                while k < n and src[k] == '=':
                    k += 1
                if k < n and src[k] == '[':
                    level = k - j - 1
                    closer = ']' + '=' * level + ']'
                    end = src.find(closer, k + 1)
                    end = n if end == -1 else end + len(closer)
                    yield 'comment', src[i:end]
                    i = end
                    continue
            # Short comment to EOL.
            end = src.find('\n', j)
            end = n if end == -1 else end
            yield 'comment', src[i:end]
            i = end
            continue
        if c == '[':
            j = i + 1
            while j < n and src[j] == '=':
                j += 1
            if j < n and src[j] == '[':
                level = j - i - 1
                closer = ']' + '=' * level + ']'
                end = src.find(closer, j + 1)
                end = n if end == -1 else end + len(closer)
                yield 'string', src[i:end]
                i = end
                continue
        if c in ('"', "'"):
            quote = c
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == quote:
                    j += 1
                    break
                if src[j] == '\n':
                    break
                j += 1
            yield 'string', src[i:j]
            i = j
            continue
        # Plain code run until next interesting byte.
        j = i
        while j < n and src[j] not in '-[\'"':
            j += 1
        if j == i:
            # `-` or `[` not followed by comment/string opener.
            yield 'code', src[i]
            i += 1
        else:
            yield 'code', src[i:j]
            i = j


def replace_mode(src: str, replacement: str) -> str:
    out = []
    for kind, text in _strip_lua_strings_and_comments(src):
        if kind == 'code':
            text = _BARE_PACKAGE_RE.sub(replacement, text)
        out.append(text)
    return ''.join(out)


def prepend_mode(src: str, replacement: str) -> str:
    header = f'package = {replacement}\n'
    # Preserve a leading shebang / `#!`-style line if present.
    if src.startswith('#!'):
        nl = src.find('\n')
        if nl != -1:
            return src[:nl + 1] + header + src[nl + 1:]
    return header + src


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('file', type=Path,
        help='Input Lua file (use - for stdin).')
    ap.add_argument('-m', '--mode',
        choices=('prepend', 'replace'), default='prepend',
        help='How to rewrite (default: prepend).')
    ap.add_argument('-r', '--replacement', default='{}',
        help='Replacement expression (default: `{}`).')
    ap.add_argument('-o', '--out', type=Path,
        help='Write to this path (default: stdout).')
    ap.add_argument('-i', '--inplace', action='store_true',
        help='Overwrite the input file in-place.')
    args = ap.parse_args()

    if args.inplace and args.out is not None:
        ap.error('--inplace and --out are mutually exclusive')

    if str(args.file) == '-':
        src = sys.stdin.read()
    else:
        src = args.file.read_text()

    if args.mode == 'prepend':
        out = prepend_mode(src, args.replacement)
    else:
        out = replace_mode(src, args.replacement)

    if args.inplace:
        args.file.write_text(out)
    elif args.out is not None:
        args.out.write_text(out)
    else:
        sys.stdout.write(out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
