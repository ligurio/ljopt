# Needs the multi-line repro: the divergence depends on trace shape,
# and the branches that look dead are load-bearing.
luajit -joff             findings/luajit-fold-off-ffi-field/repro.lua
luajit -Ohotloop=1,-fold findings/luajit-fold-off-ffi-field/repro.lua
