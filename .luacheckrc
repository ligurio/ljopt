std = "luajit"

max_code_line_length = 80
max_comment_line_length = 66

files["tests/buggy_luajit_tests.lua"] = {
    max_comment_line_length = 105
}

ignore = {
    -- Accessing an undefined field of a global variable <os>.
    "143/os",
    -- Accessing an undefined field of a global variable <string>.
    "143/string",
    -- Accessing an undefined field of a global variable <table>.
    "143/table",
    -- Unused argument <self>.
    "212/self",
    -- Unused variable with `_` prefix.
    "212/_.*",
    -- Unused loop variable with `_` prefix.
    "213/_.*",
}

-- The file contains a code borrowed from LuaJIT. Changes to it
-- complicate synchronization with upstream.
files["ljopt/ir_dump.lua"] = {
    max_comment_line_length = 80
}

files["tests/buggy_luajit_tests.lua"] = {
    max_comment_line_length = 105
}

files["tests/*tests.lua"] = {
    ignore = {
        -- Shadowing an upvalue.
        "431",
    }
}

include_files = {
    '.luacheckrc',
    '*.rockspec',
    'ljopt/**/**.lua',
    'tests/**.lua',
}

exclude_files = {
    '.rocks',
    'tests/tap.lua',
    'tests/lj_*.lua',
    'ljopt/bc_dump.lua',
}
