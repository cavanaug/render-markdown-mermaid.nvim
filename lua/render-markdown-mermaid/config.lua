local M = {}

local function has_executable(command)
    return vim.fn.executable(command) == 1
end

---@param cmd? string[]
---@return string[]
function M.resolve_cmd(cmd)
    if cmd and cmd[1] then
        return vim.deepcopy(cmd)
    end
    if has_executable('bm') then
        return { 'bm' }
    end
    if has_executable('mermaid-ascii') then
        return { 'mermaid-ascii' }
    end
    return { 'bm' }
end

M.default = {
    mode = 'below_raw',
    cmd = { 'bm' },
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
        pending = '󱎫 Mermaid rendering...',
        error = '󱂅 Mermaid render failed',
    },
}

---@param opts? table
---@return table
function M.merge(opts)
    local merged = vim.tbl_deep_extend('force', {}, M.default, opts or {})
    if not merged.cmd or not merged.cmd[1] or not opts or opts.cmd == nil then
        merged.cmd = M.resolve_cmd(opts and opts.cmd or nil)
    end
    return merged
end

return M
