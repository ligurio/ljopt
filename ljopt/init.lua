local runtime = require("ljopt.runtime")
local smtlib_ir = require("ljopt.ir_smtlib")
local is_jit = (tostring(getmetatable):match("builtin") ~= nil)

if (not is_jit) then
    error("requires LuaJIT")
end

local VERSION = "0.0.1"

return {
    ir = {
	    record = runtime.record_sandboxed,
	    traces_to_smt = smtlib_ir.traces_to_smt,
	    translate_to_smt = smtlib_ir.translate_to_smt,
    },

    VERSION = VERSION,
}
