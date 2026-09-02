# Root cause: TOBIT clobbers a loop-invariant operand's register

One register-allocation defect in `asm_tobit` (`lj_asm_x86.h`) causes
two separately-found miscompiles:

* `findings/luajit-o3-lost-hstore` -- wrong result at **default -O3**
* `findings/luajit-fold-off-wrong-table` -- wrong result at `-O3,-fold`

Both are fixed by `fix.patch`, and each was confirmed on two
independent generated programs.

## The defect

`asm_tobit` lowers `TOBIT x` as the bias-add trick: add 2^52 to `x`
as a double, then take the low 32 bits.

```c
Reg tmp = ra_noreg(IR(ir->op1)->r) ?
	    ra_alloc1(as, ir->op1, RSET_FPR) :   /* no reg yet -> take op1's */
	    ra_scratch(as, RSET_FPR);
emit_rr(as, XO_MOVDto, tmp, dest);
emit_mrm(as, XO_ADDSD, tmp, right);          /* destructive: tmp += bias */
ra_left(as, tmp, ir->op1);                   /* coalesce op1 into tmp */
```

The add is destructive, so `tmp` must not be a register whose value is
still needed. The `ra_noreg` test is meant to decide that, but LuaJIT
assembles backwards: an operand whose only other use is *earlier in the
loop body*, reached through the back-edge, has no register assigned yet
at this point. `ra_noreg` reports "free to clobber", `ra_left` coalesces
the operand into `tmp`, and the bias-add destroys a value that the top
of the loop still reads on the next iteration.

`asm_loop` cannot repair it: it reconciles PHIs
(`asm_phi_shuffle`/`asm_phi_copyspill`), and a loop-invariant is not a
PHI. The allocator's own protection is explicitly only a preference:

```c
/* Invariants should preferably get unmodified registers. */
```

and it does not apply here anyway, because the clobber comes from the
same instruction that allocated the register.

## Machine-code evidence

From `repro-foldoff.lua` at `-O3,-fold`, where
`0051 = CONV +127 num.int` is loop-invariant and `0106 = TOBIT 0051`:

```
->LOOP:
  ucomisd xmm9, xmm5      ; guard 0086: 127.0 < 64536.0, reads xmm5
  ...
  addsd   xmm5, xmm8      ; TOBIT bias-add -- destroys xmm5
  movd    ebx, xmm5
  jle ->LOOP              ; back-edge; nothing restores xmm5
```

From the second iteration the guard compares against ~2^52, an
always-true test fails, and the side trace behind that exit runs the
arm the source never selects.

## The fix

When the TOBIT is in the variant part and its operand comes from the
invariant part, allocate the operand its own register and copy it into
the scratch instead of coalescing. See `fix.patch`.

## Validation

With the patch applied (rebuild via cmake in the LuaJIT tree):

| case | unpatched | patched |
|---|---|---|
| `o3-lost-hstore` one-liner, `-O3` | 100 (wrong) | 400 |
| generated seed 200876, `-O3` | wrong | correct |
| `repro-foldoff.lua`, `-O3,-fold` | 825351 (wrong) | nil |
| generated seed 220864, `-Ohotloop=1,-fold` | wrong | correct |

The JIT stays fully active: the same number of traces is compiled and
TOBIT is still emitted, so the patch fixes the allocation rather than
suppressing compilation. Measure trace counts with
`LUA_PATH=<tree>/src/?.lua` set, or `jit.dump` silently fails and the
count reads zero.

## Not fixed by this patch (separate bugs)

* `findings/luajit-dce-snapshot-clobber` -- still reproduces.
* Four FFI programs that diverge only at `-Ofold` off. Same coarse
  flag fingerprint, but unaffected by this patch, so a different
  defect.
