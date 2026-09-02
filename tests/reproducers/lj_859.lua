-- Incorrect recording of math.ceil() result sign for -1 < x < -0.5
-- (LuaJIT#859), x86/x64 only.
-- See: https://github.com/LuaJIT/LuaJIT/issues/859
-- See also: https://github.com/tarantool/luajit/commit/439a3a039ebc8f9e9175a8f98e3d8a1249749c27

-- tostring() keeps the sign of the returned -0.0.
assert(tostring(math.ceil(-0.9)) == "-0", "assertion is violated")
