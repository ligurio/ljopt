-- cvc5 backend, drop-in for ljopt/smtlib2.lua (the z3 one).
-- Same API: new(), :parse(str), :check(str), .result.
--
-- Uses cvc5's C API (include/cvc5/c) through LuaJIT's FFI, the
-- same way the z3 backend binds libz3. SMT-LIB text reaches the
-- solver through the C input parser, which is the counterpart of
-- Z3_solver_from_string.
--
-- A recent cvc5 is required, which rules out the packaged
-- 1.1.2 on two counts: it exports no cvc5_* symbols at all
-- (the C API arrived in 1.2.0), and it mis-answers some of
-- these formulas -- returning sat where the traces are
-- equivalent, with its own --check-models then rejecting the
-- model it had just produced. CI pins the 1.3.4 release; also
-- verified against 1.3.5.dev.

local ljopt_config = require("ljopt.config")

local is_ffi, ffi = pcall(require, "ffi")

if is_ffi == false then
    error("requires FFI")
end

ffi.cdef[[
typedef struct Cvc5TermManager Cvc5TermManager;
typedef struct Cvc5 Cvc5;
typedef struct cvc5_result_t* Cvc5Result;
typedef struct Cvc5SymbolManager Cvc5SymbolManager;
typedef struct cvc5_cmd_t* Cvc5Command;
typedef struct Cvc5InputParser Cvc5InputParser;

Cvc5TermManager* cvc5_term_manager_new(void);
void cvc5_term_manager_delete(Cvc5TermManager* tm);
Cvc5* cvc5_new(Cvc5TermManager* tm);
void cvc5_delete(Cvc5* slv);
void cvc5_set_option(Cvc5* slv, const char* option, const char* value);
Cvc5Result cvc5_check_sat(Cvc5* slv);
const char* cvc5_get_version(Cvc5* slv);
bool cvc5_result_is_sat(const Cvc5Result result);
bool cvc5_result_is_unsat(const Cvc5Result result);
bool cvc5_result_is_unknown(const Cvc5Result result);

Cvc5SymbolManager* cvc5_symbol_manager_new(Cvc5TermManager* tm);
void cvc5_symbol_manager_delete(Cvc5SymbolManager* sm);
Cvc5InputParser* cvc5_parser_new(Cvc5* slv, Cvc5SymbolManager* sm);
void cvc5_parser_delete(Cvc5InputParser* parser);
void cvc5_parser_set_str_input(Cvc5InputParser* parser, int lang,
                               const char* input, const char* name);
Cvc5Command cvc5_parser_next_command(Cvc5InputParser* parser,
                                     const char** error_msg);
const char* cvc5_cmd_invoke(Cvc5Command cmd, Cvc5* slv,
                            Cvc5SymbolManager* sm);
]]

-- Two libraries with a clean split: the solver entry points live
-- in libcvc5, the input parser and symbol manager in
-- libcvc5parser. Calls have to go through the matching handle.
local cvc5 = ffi.load("cvc5")
local parserlib = ffi.load("cvc5parser")

-- Run every SMT-LIB command in `str` against a fresh solver, so
-- declarations and assertions land in its context. Returns the
-- handles plus a parse/type error message, or nil when clean.
local function feed(str)
    local tm = cvc5.cvc5_term_manager_new()
    local slv = cvc5.cvc5_new(tm)
    cvc5.cvc5_set_option(slv, "tlimit", ljopt_config.get_solver_timeout_ms())
    -- The formulas carry no (set-logic); saying so up front keeps
    -- cvc5 from warning about it on every query.
    cvc5.cvc5_set_option(slv, "force-logic", "ALL")

    local sm = parserlib.cvc5_symbol_manager_new(tm)
    local parser = parserlib.cvc5_parser_new(slv, sm)
    -- The input has to be configured before commands can be
    -- pulled; 0 is CVC5_INPUT_LANGUAGE_SMT_LIB_2_6.
    parserlib.cvc5_parser_set_str_input(parser, 0, str, "ljopt")

    local errp = ffi.new("const char*[1]")
    local err
    while true do
        errp[0] = nil
        local cmd = parserlib.cvc5_parser_next_command(parser, errp)
        if errp[0] ~= nil then
            err = ffi.string(errp[0])
            break
        end
        if cmd == nil then break end
        parserlib.cvc5_cmd_invoke(cmd, slv, sm)
    end
    return slv, tm, sm, parser, err
end

local function release(slv, tm, sm, parser)
    parserlib.cvc5_parser_delete(parser)
    parserlib.cvc5_symbol_manager_delete(sm)
    cvc5.cvc5_delete(slv)
    cvc5.cvc5_term_manager_delete(tm)
end

-- Function parses a buffer with SMT-LIB. True when cvc5 accepts
-- it, false on a parse/type error.
local function parse_smtlib2_string(_self, str)
    if type(str) ~= "string" then
        error("'str' is not a string")
    end
    local slv, tm, sm, parser, err = feed(str)
    release(slv, tm, sm, parser)
    return err == nil
end

-- Function checks whether the logical context is satisfiable,
-- and return the result.
-- Returns:
-- -1 - UNSAT
--  0 - UNKNOWN
--  1 - SAT
local result = {
    UNSAT = -1,
    UNKNOWN = 0,
    SAT = 1,
}

local function check(_self, str)
    if type(str) ~= "string" then
        error("the given argument should be a string", 2)
    end
    local slv, tm, sm, parser, err = feed(str)
    local res = result.UNKNOWN
    if err == nil then
        local r = cvc5.cvc5_check_sat(slv)
        if cvc5.cvc5_result_is_unsat(r) then
            res = result.UNSAT
        elseif cvc5.cvc5_result_is_sat(r) then
            res = result.SAT
        end
    end
    release(slv, tm, sm, parser)
    return res
end

local mt = {
    __index = {
        parse = parse_smtlib2_string,
        check = check,
        result = result,
    },
}

local function new()
    -- Build and tear down once, so a missing or too-old cvc5
    -- fails here rather than on the first query.
    local tm = cvc5.cvc5_term_manager_new()
    local slv = cvc5.cvc5_new(tm)
    print("cvc5 version: ", ffi.string(cvc5.cvc5_get_version(slv)))
    cvc5.cvc5_delete(slv)
    cvc5.cvc5_term_manager_delete(tm)

    return setmetatable({}, mt)
end

return {
    new = new,
}
