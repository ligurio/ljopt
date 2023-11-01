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

include_files = {
    '.luacheckrc',
    '*.rockspec',
    '**/*.lua',
}

exclude_files = {
    '.rocks',
    'tests/opt/',
    'trash/',
}
