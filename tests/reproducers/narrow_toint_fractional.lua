-- The same narrowing bug through the IRCONV_ANY sink instead of
-- TOBIT: `string.sub`'s start argument goes through
-- lj_opt_narrow_toint(), which emits `CONV int num ANY`. Narrowing
-- rewrites `(int)(y + 3)` to `(int)y + 3`, so truncation happens
-- before the addition: trunc(-0.5) + 3 = 3, trunc(2.5) = 2.
--
-- Fixed in lua_patches/fixes/luajit-v2.1-narrow-guarded-sink.patch,
-- which is applied to the main build only.
local y = -0.5
local s = "abcdef"
local expected = s:sub(y + 3)
local last
for _ = 1, 400 do
  last = s:sub(y + 3)
end

assert(last == expected,
    "narrowing across ADD rounds too early: string.sub")
