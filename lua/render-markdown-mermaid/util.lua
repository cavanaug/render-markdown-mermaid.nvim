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
---@param width? integer Fill each virtual row to this display-cell width.
---@return render.md.mark.Line[]
function M.to_virt_lines(lines, width)
    local virt_lines = {}
    for _, line in ipairs(lines) do
        local chunks = { { line, 'RenderMarkdownCode' } }
        local fill = width and math.max(0, width - vim.fn.strdisplaywidth(line)) or 0
        if fill > 0 then
            -- Virtual-line highlights otherwise stop at the final character.
            -- Keep background-only padding out of the cached/copyable output.
            chunks[#chunks + 1] = { string.rep(' ', fill), 'RenderMarkdownCode' }
        end
        virt_lines[#virt_lines + 1] = chunks
    end
    return virt_lines
end

return M
