local M = {}
local DEFAULT_RENDERERS = { 'bm', 'mermaid-ascii' }

local function has_executable(command)
    return vim.fn.executable(command) == 1
end

---@return table<string, boolean>
function M.available_default_renderers()
    local available = {}
    for _, command in ipairs(DEFAULT_RENDERERS) do
        available[command] = has_executable(command)
    end
    return available
end

---@param cmd? string[]
---@param available? table<string, boolean>
---@return string[]
function M.resolve_cmd(cmd, available)
    if cmd and cmd[1] then
        return vim.deepcopy(cmd)
    end
    available = available or M.available_default_renderers()
    for _, command in ipairs(DEFAULT_RENDERERS) do
        if available[command] then
            return { command }
        end
    end
    return { DEFAULT_RENDERERS[1] }
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
    local has_user_cmd = opts and opts.cmd and opts.cmd[1]
    merged._cmd_source = has_user_cmd and 'user' or 'auto'
    if merged._cmd_source == 'auto' or not merged.cmd or not merged.cmd[1] then
        merged.cmd = M.resolve_cmd(nil)
    end
    return merged
end

return M
