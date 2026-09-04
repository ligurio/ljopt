-- Requires installed z3 package.
-- Usage:
-- local smt = require("ljopt.smtlib2").new()
-- assert(smt:parse("(declare-const p0 Bool)") == true)
-- assert(smt:check("(declare-const p0 Bool)") == 1)
-- smt = nil
--
-- Z3 C API: https://z3prover.github.io/api/html/

local ljopt_config = require("ljopt.config")

local is_ffi, ffi = pcall(require, "ffi")

if is_ffi == false then
    error("requires FFI")
end

ffi.cdef[[
struct Z3_ast_vector;
struct Z3_config;
struct Z3_context;
struct Z3_func_decl;
struct Z3_solver;
struct Z3_sort;
struct Z3_string;
struct Z3_symbol;

typedef struct Z3_ast_vector *Z3_ast_vector;
typedef struct Z3_config *Z3_config;
typedef struct Z3_context *Z3_context;
typedef struct Z3_func_decl *Z3_func_decl;
typedef struct Z3_solver *Z3_solver;
typedef struct Z3_sort *Z3_sort;
typedef struct Z3_string *Z3_string;
typedef struct Z3_symbol *Z3_symbol;

Z3_config Z3_mk_config(void);
void Z3_set_param_value(Z3_config c,
                        Z3_string param_id,
                        Z3_string param_value);
Z3_context Z3_mk_context(Z3_config c);
Z3_ast_vector Z3_parse_smtlib2_string(Z3_context c,
                                      Z3_string str,
                                      unsigned num_sorts,
                                      Z3_symbol const sort_names[],
                                      Z3_sort const sorts[],
                                      unsigned num_decls,
                                      Z3_symbol const decl_names[],
                                      Z3_func_decl const decls[]);

unsigned Z3_ast_vector_size(Z3_context c, Z3_ast_vector v);
Z3_string Z3_ast_vector_to_string(Z3_context c, Z3_ast_vector v);

typedef enum {
    Z3_L_FALSE = -1,
    Z3_L_UNDEF,
    Z3_L_TRUE
} Z3_lbool;

Z3_solver Z3_mk_solver(Z3_context c);
void Z3_solver_inc_ref(Z3_context c, Z3_solver s);
void Z3_solver_dec_ref(Z3_context c, Z3_solver s);
void Z3_solver_from_string(Z3_context c, Z3_solver s, Z3_string str);
Z3_lbool Z3_solver_check(Z3_context c, Z3_solver s);

void Z3_get_version(
    unsigned *major,
    unsigned *minor,
    unsigned *build_number,
    unsigned *revision_number
);

void Z3_del_config(Z3_config c);
void Z3_del_context(Z3_context c);

void free(void *ptr);
]]

local z3 = ffi.load("z3")

-- Function parses a buffer with SMT-LIB.
local function parse_smtlib2_string(self, str)
    if type(str) ~= "string" then
        error("'str' is not a string")
    end
    local smtlib2_buf = ffi.cast("Z3_string", str)
    local num_sorts = ffi.cast("unsigned", 0)
    local sort_names = ffi.cast("const Z3_symbol *", 0)
    local sorts = ffi.cast("const Z3_sort *", 0)
    local num_decls = ffi.cast("unsigned", 0)
    local decl_names = ffi.cast("Z3_symbol *", 0)
    local decls = ffi.cast("Z3_func_decl *", 0)
    -- luacheck: no unused
    local res = z3.Z3_parse_smtlib2_string(self.ctx, smtlib2_buf,
                                           num_sorts, sort_names, sorts,
                                           num_decls, decl_names, decls)

    return true
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

local function check(self, str)
    if type(str) ~= "string" then
        error("the given argument should be a string", 2)
    end
    local solver = z3.Z3_mk_solver(self.ctx)
    z3.Z3_solver_inc_ref(self.ctx, solver)
    z3.Z3_solver_from_string(self.ctx, solver, ffi.cast("Z3_string", str))
    local res = z3.Z3_solver_check(self.ctx, solver)
    z3.Z3_solver_dec_ref(self.ctx, solver)

    return tonumber(res)
end

local function free(self)
    z3.Z3_del_context(self.ctx)
end

local mt = {
    __gc = free,
    __index = {
        parse = parse_smtlib2_string,
        check = check,
        result = result,
    },
}

local function get_z3_version()
    local major = ffi.new("unsigned[1]")
    local minor = ffi.new("unsigned[1]")
    local build = ffi.new("unsigned[1]")
    local revision = ffi.new("unsigned[1]")
    z3.Z3_get_version(major, minor, build, revision)
    major = tonumber(major[0])
    minor = tonumber(minor[0])
    build = tonumber(build[0])
    revision = tonumber(revision[0])
    local version_string = string.format("%d.%d.%d.%d",
        major, minor, build, revision)
    return {
        major = major,
        minor = minor,
        build = build,
        revision = revision,
        version_string = version_string
    }
end

local function version_lt(version1, version2)
    if version1.major ~= version2.major then
        return version1.major < version2.major
    else
        return version1.minor < version2.minor
    end
end

local function new()
    local z3_version = get_z3_version()
    print(("SMT backend: Z3 %s"):format(z3_version.version_string))
    local Z3_MIN_MAJOR = 4
    local Z3_MIN_MINOR = 15
    if version_lt(get_z3_version(), {
        major = Z3_MIN_MAJOR, minor = Z3_MIN_MINOR }) then
        error(("The version of Z3 library is less than supported (%s, %d): %s"):
            format(z3_version.version_string, Z3_MIN_MAJOR, Z3_MIN_MINOR))
    end
    local self = {}
    local cfg = z3.Z3_mk_config()
    z3.Z3_set_param_value(cfg, ffi.cast("Z3_string", "timeout"),
                          ffi.cast("Z3_string",
                          ljopt_config.get_solver_timeout_ms()))
    self.ctx = z3.Z3_mk_context(cfg)
    z3.Z3_del_config(cfg)

    return setmetatable(self, mt)
end

return {
    new = new,
}
