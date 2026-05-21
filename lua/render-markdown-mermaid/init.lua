local config_mod = require('render-markdown-mermaid.config')
local display = require('render-markdown-mermaid.display')

local M = {
    config = nil,
}

local function setup_render_markdown()
    if not M.config or not M.config.auto_setup_render_markdown then
        return
    end

    local ok, render_markdown = pcall(require, 'render-markdown')
    if not ok then
        return
    end

    local opts = vim.deepcopy(M.config.render_markdown or {})
    render_markdown.setup(opts)
end

local function render_buffer(args)
    local buf = args.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    display.schedule(buf, M.config, M.config.debounce)
end

---@param opts? table
function M.setup(opts)
    M.config = config_mod.merge(opts)

    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidPending', { link = 'DiagnosticInfo' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidError', { link = 'DiagnosticWarn' })

    local group = vim.api.nvim_create_augroup('RenderMarkdownMermaid', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'TextChanged', 'TextChangedI', 'InsertEnter', 'InsertLeave', 'CursorMoved', 'CursorMovedI' }, {
        group = group,
        callback = render_buffer,
    })
    vim.api.nvim_create_autocmd('BufDelete', {
        group = group,
        callback = function(args)
            display.clear(args.buf)
        end,
    })

    setup_render_markdown()
    render_buffer({ buf = vim.api.nvim_get_current_buf() })
end

return M
