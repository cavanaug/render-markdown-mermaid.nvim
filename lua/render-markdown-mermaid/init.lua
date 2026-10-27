local config_mod = require('render-markdown-mermaid.config')
local display = require('render-markdown-mermaid.display')
local scroll = require('render-markdown-mermaid.scroll')
local navigation = require('render-markdown-mermaid.navigation')

local M = {
    config = nil,
}
local configured_width = nil
local configured_commands = {}

local function cycle_renderer(backwards)
    local available = config_mod.available_renderers()
    for name, command in pairs(configured_commands) do
        -- A user command may name an executable outside PATH or a wrapper.
        if vim.fn.executable(command[1]) == 1 then available[name] = true end
    end
    local selected = config_mod.next_renderer(M.config.cmd, available, backwards)
    if not selected then
        vim.notify('No supported Mermaid renderer is installed.', vim.log.levels.WARN)
        return
    end
    if selected == config_mod.renderer_name(M.config.cmd) then
        vim.notify('Mermaid renderer: ' .. selected .. ' (only installed backend)', vim.log.levels.INFO)
        return
    end

    local options = vim.deepcopy(M.config)
    options.cmd = vim.deepcopy(configured_commands[selected] or { selected })
    options.width = configured_width
    M.config = config_mod.merge(options)
    M.config._cmd_source = 'cycle'
    -- Use a fresh config table: in-flight renders retain their original
    -- command/cache key and must not be interpreted as the new backend.
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            local ft = vim.bo[buf].filetype
            if ft == 'markdown' or ft == 'mdx' or ft == 'markdown.mdx' then
                display.schedule(buf, M.config, 0)
            end
        end
    end
    vim.notify('Mermaid renderer: ' .. selected, vim.log.levels.INFO)
end

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
    configured_width = opts and opts.width
    configured_commands = {}
    local initial = config_mod.renderer_name(M.config.cmd)
    -- Only retain explicit overrides; automatic PATH choices are rechecked.
    if initial and M.config._cmd_source == 'user' then
        configured_commands[initial] = vim.deepcopy(M.config.cmd)
    end

    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidPending', { link = 'DiagnosticInfo' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidError', { link = 'DiagnosticWarn' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidNotice', { link = 'DiagnosticHint' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidScroll', { link = 'DiagnosticInfo' })

    local group = vim.api.nvim_create_augroup('RenderMarkdownMermaid', { clear = true })
    vim.api.nvim_create_user_command('MermaidFocus', function()
        scroll.focus(vim.api.nvim_get_current_buf())
    end, { desc = 'Toggle navigating the Mermaid diagram under the cursor', force = true })
    vim.api.nvim_create_user_command('MermaidCycle', function(args)
        cycle_renderer(args.bang)
    end, { bang = true, desc = 'Cycle installed Mermaid renderers (! for previous)', force = true })
    vim.keymap.set('n', '<Plug>(MermaidCycle)', '<Cmd>MermaidCycle<CR>', { desc = 'Next Mermaid renderer' })
    vim.keymap.set('n', '<Plug>(MermaidCycleBack)', '<Cmd>MermaidCycle!<CR>', { desc = 'Previous Mermaid renderer' })
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
