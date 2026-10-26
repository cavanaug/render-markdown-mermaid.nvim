local config_mod = require('render-markdown-mermaid.config')
local display = require('render-markdown-mermaid.display')
local scroll = require('render-markdown-mermaid.scroll')
local navigation = require('render-markdown-mermaid.navigation')

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
    scroll.clear()
    M.config = config_mod.merge(opts)

    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidPending', { link = 'DiagnosticInfo' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidError', { link = 'DiagnosticWarn' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidNotice', { link = 'DiagnosticHint' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidScroll', { link = 'DiagnosticInfo' })

    local group = vim.api.nvim_create_augroup('RenderMarkdownMermaid', { clear = true })
    vim.api.nvim_create_user_command('MermaidFocus', function()
        scroll.focus(vim.api.nvim_get_current_buf())
    end, { desc = 'Toggle navigating the Mermaid diagram under the cursor', force = true })
    navigation.setup(M.config.focus_key, group)
    vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave', 'WinClosed', 'BufEnter', 'WinEnter' }, {
        group = group,
        callback = function() vim.schedule(scroll.check) end,
    })
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        group = group,
        callback = function(args) scroll.changed(args.buf) end,
    })
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'WinScrolled' }, {
        group = group,
        callback = scroll.check,
    })
    vim.api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, {
        group = group,
        callback = function()
            local seen = {}
            for _, win in ipairs(vim.api.nvim_list_wins()) do
                local buf = vim.api.nvim_win_get_buf(win)
                if not seen[buf] then
                    seen[buf] = true
                    display.schedule(buf, M.config, M.config.debounce)
                end
            end
        end,
    })
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
