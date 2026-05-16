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

---@param key string
function M.clear(key)
    M.values[key] = nil
end

function M.reset()
    M.values = {}
end

return M
