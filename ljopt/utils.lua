local function merge_tables(t1, t2)
    local merged = {}
    local all_keys = {}
    for k, _v in pairs(t1) do
        all_keys[k] = true
        assert(t2[k] ~= nil, "key does not exist " .. k)
    end
    for k, _v in pairs(t2) do
        assert(t1[k] ~= nil, "key does not exist " .. k)
    end

    for k, _v in pairs(all_keys) do
        assert(t1[k] ~= nil, "t1 is nil")
        assert(t2[k] ~= nil, "t2 is nil")
        merged[k] = {t1[k], t2[k]}
    end

    return merged
end

return {
    merge_tables = merge_tables,
}
