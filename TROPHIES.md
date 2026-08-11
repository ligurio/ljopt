### LuaJIT

- Incorrect -0 direction for JITed loop,
  https://github.com/LuaJIT/LuaJIT/issues/1432

- `lj_opt_narrow` moves an unguarded num->int conversion inside an
  ADD/SUB, which changes the result whenever the num operand is not
  an integer. Found by the irfuzz `--narrow` enumeration; not yet
  reported upstream.

  `narrow_conv_backprop` accepts a leaf it cannot narrow by paying
  for one conversion (`count <= 1`), so `(int)(x + (double)i)` is
  rewritten to `(int)x + i`. Rounding then happens before the
  addition instead of after it, and the two differ for every
  fractional `x`. The `IRCONV_ANY` sinks reach this from
  `lj_opt_narrow_toint` (`string.sub`, `string.rep`, `table.insert`,
  ... in lj_ffrecord.c) and the `TOBIT` sink from `bit.tobit`.

  ```lua
  local s = "abcdef"
  local ys = {}
  for i = 1, 400 do ys[i] = -0.5 end
  local function f(y) return s:sub(y + 3) end
  local out = {}
  for i = 1, 400 do out[i] = f(ys[i]) end
  print(out[1], out[400])   --> bcdef   cdef

  local zs = {}
  for i = 1, 400 do zs[i] = 0.5 end
  local function g(z) return bit.tobit(z + 1) end
  local o2 = {}
  for i = 1, 400 do o2[i] = g(zs[i]) end
  print(o2[1], o2[400])     --> 2   1
  ```

  Interpreted, `s:sub(-0.5 + 3)` truncates 2.5 to 2 and
  `bit.tobit(0.5 + 1)` rounds 1.5 to 2; the compiled trace narrows
  both and answers as if the conversion came first. `y`/`z` have to
  come out of a table so they stay real SLOADs -- a literal is
  constant-folded before narrowing ever runs.
