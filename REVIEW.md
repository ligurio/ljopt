# Code Review Guidelines

## Always check
- Newly implemented IR instructions have tests for it as a Lua chunk
- Newly implemented IR instruction files are added to ljopt-scm-1.rockspec
- No regressions introduced. If something worked before it should keep working
- Comments should match with the code content

## Style
- Comments before the line they are commenting, if it's separate sentence it ends with a dot
- Error messages are clear
- Lua supports ' and " as quotes. They should be unified in a file,
but can be different for different files
- No newly `assert()` used if it means unreachable, we have `utils.unreachable` for this paths
- Similar strings sorted in alphabetical order
- Variable names should be in snake_case

## Commits
- Commit contains only required diff 
- Commit separated by header and body
- Commit body mentions all the changes done in comment
- Commit header is concise