local M = {
    values = {},
}

---@param key string
---@return table|nil
function M.get(key)
    return M.values[key]
end

---@param key string
---@param value table
function M.set(key, value)
    M.values[key] = value
end

return M
