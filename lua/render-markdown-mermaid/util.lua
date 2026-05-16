local M = {}

---@param node TSNode
---@param buf integer
---@return string
function M.node_text(node, buf)
    return vim.treesitter.get_node_text(node, buf) or ''
end

---@param value string
---@return string
function M.hash(value)
    return vim.fn.sha256(value)
end

---@param lines string[]
---@return render.md.mark.Line[]
function M.to_virt_lines(lines)
    local virt_lines = {}
    for _, line in ipairs(lines) do
        virt_lines[#virt_lines + 1] = { { line, 'RenderMarkdownCode' } }
    end
    return virt_lines
end

return M
