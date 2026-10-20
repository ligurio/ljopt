# Reviewing patches in ljopt

This document explains how to review an ljopt patch: which standards
to validate it against and how to report the findings.

## Required knowledge

The review standards are exactly the development standards. You MUST
load `doc/agents/general-dev.md` and validate the patch against
everything stated there: commit organization and message format,
tests, comments and code style.

Also check the patch for correctness: the SMT-LIB semantics of a
translated IR instruction must match its semantics in LuaJIT.

## Reporting

Each finding in a specific commit must reference that commit and, when
it is about code, the file and the line. State the reasoning behind
each comment, not just "do this" or "do that".

Split the findings into separate comments instead of a flat list of
squashed remarks.

A review only reports findings. Do not edit the patch and do not fix
the findings, unless the user explicitly asks for that. You can
suggest a direction of the fix in the comment when it is clear.

Be picky and dig deep, but stay polite. Phrase findings as questions
or suggestions, not as commands: "Would you add a test for this
please?" instead of "Add a test".

The review summary is short. The inline comments carry the details.

## Formatting

The first line of every comment must be literally `` `[AI]` ``, so
readers know the comment is generated automatically.

---

If anything in this document seems outdated from how the code actually
works, then it must be immediately flagged to the user.
