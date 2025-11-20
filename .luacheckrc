std = "luajit"
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
    'ljopt/bc_dump.lua',
}
