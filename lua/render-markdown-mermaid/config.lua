local M = {}

M.default = {
    mode = 'below_raw',
    cmd = { 'mermaid-ascii' },
    auto_setup_render_markdown = true,
    debounce = 150,
    timeout = 2000,
    cache = true,
    hide_source = false,
    max_block_lines = 200,
    render_markdown = {
        file_types = { 'markdown', 'mdx', 'markdown.mdx' },
    },
    cli = {
        ascii = false,
        border_padding = 1,
        padding_x = 5,
        padding_y = 5,
    },
    ui = {
        icons = true,
        pending = '󱎫 Mermaid rendering...',
        error = '󱂅 Mermaid render failed',
    },
}

---@param opts? table
---@return table
function M.merge(opts)
    return vim.tbl_deep_extend('force', {}, M.default, opts or {})
end

return M
