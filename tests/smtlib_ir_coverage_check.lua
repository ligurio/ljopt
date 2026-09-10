-- Translate a Lua file that exercises many LuaJIT IR instructions
-- (smtlib_ir_coverage.lua) to SMT-LIB, then check that every
-- emitted formula is accepted by the solver backend chosen with
-- LJOPT_SMT.  tests.smtlib2 dispatches to cvc5 by default or z3.
--
-- Usage:
--   luajit tests/smtlib_ir_coverage_check.lua <coverage.lua>
--
-- Exits with 0 when every formula parses and with 1 otherwise.

local ljopt = require("ljopt")
local ljopt_config = require("ljopt.config")
local smt = require("tests.smtlib2").new()
local smt_constants = require("ljopt.smt_constants")

-- The corpus exercises IR instructions ljopt cannot translate
-- yet (upvalue reads, untyped guards, ...).  Strict mode turns
-- such NYI nodes into an assertion, so disable it, like
-- tests/buggy_luajit_tests.lua does.
ljopt_config.set_strict_mode(false)

local coverage_path = arg[1]
if coverage_path == nil then
    io.stderr:write("usage: smtlib_ir_coverage_check.lua <coverage.lua>\n")
    os.exit(1)
end

local fh = assert(io.open(coverage_path, "r"))
local lua_code = fh:read("*a")
fh:close()

local formulas = ljopt.ir.traces_to_smt(lua_code)
assert(next(formulas) ~= nil, "no SMT formulas were recorded")

local checked = 0
for _id, formula in pairs(formulas) do
    checked = checked + 1
    local smt_formula = smt_constants.LJOPT_SMTLIB .. formula
    if not smt:parse(smt_formula) then
        io.stderr:write(("failed to parse SMT-LIB for trace %s\n"):format(
            tostring(_id)))
        os.exit(1)
    end
end

io.stdout:write(("checked %d formulas, all parsed\n"):format(checked))
os.exit(0)
