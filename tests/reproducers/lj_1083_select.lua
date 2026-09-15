-- Incorrect recording of select() with a string index (LuaJIT#1083).
-- See: https://github.com/LuaJIT/LuaJIT/issues/1083
-- See also: https://github.com/tarantool/luajit/commit/088e2e161b8aab0ddabc89fb5d9af922536c69f1

local select = select

local function test_select(...)
  local result
  for _ = 1, 4 do
    -- Before the patch the missed coercion makes the recorder emit
    -- `int CONV  "1"  int.num index` with a string operand, so the
    -- compiled code reads an undefined value and select() returns
    -- an incorrect vararg.
    result = select('1', ...)
  end
  return result
end

assert(test_select(1, 2, 3, 4) == 1, "assertion is violated")
