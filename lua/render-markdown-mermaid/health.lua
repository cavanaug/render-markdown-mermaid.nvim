local M = {}
local config_mod = require('render-markdown-mermaid.config')

local function has_executable(command)
    return vim.fn.executable(command) == 1
end

local function has_parser(language)
    return pcall(vim.treesitter.language.add, language)
end

---@param command string
---@param available boolean
local function report_renderer(command, available)
    if available then
        vim.health.ok(('%s is available in PATH'):format(command))
    else
        vim.health.info(('%s is not available in PATH'):format(command))
    end
end

---@param command? string[]
---@return string
local function command_string(command)
    if not command or #command == 0 then
        return ''
    end
    return table.concat(command, ' ')
end

function M.check()
    local ok, render_markdown = pcall(require, 'render-markdown')
    local config_ok, mermaid = pcall(require, 'render-markdown-mermaid')
    local config = config_ok and mermaid and mermaid.config or nil
    local available = config_mod.available_default_renderers()
    local default_command = config_mod.resolve_cmd(nil, available)[1]
    local configured_command = config and config.cmd or nil
    local cmd_source = config and config._cmd_source or 'auto'

    vim.health.start('render-markdown-mermaid.nvim [dependencies]')

    if ok and render_markdown then
        vim.health.ok('render-markdown.nvim is installed')
    else
        vim.health.error('render-markdown.nvim is not available', {
            'Install MeanderingProgrammer/render-markdown.nvim.',
            'This plugin auto-configures render-markdown.nvim by default.',
        })
    end

    report_renderer('bm', available['bm'])
    report_renderer('mermaid-ascii', available['mermaid-ascii'])

    if available[default_command] then
        vim.health.ok(('Default renderer priority selects: %s'):format(default_command))
    else
        vim.health.error('No supported renderer executable is available in PATH', {
            'Install Beautiful Mermaid (bm, preferred) or mermaid-ascii, or configure setup({ cmd = { ... } }).',
            'The default renderer selection prefers bm and falls back to mermaid-ascii.',
        })
    end

    if cmd_source == 'user' then
        vim.health.info(('Configured renderer override: %s'):format(command_string(configured_command)))
    end

    vim.health.start('render-markdown-mermaid.nvim [runtime]')

    if vim.fn.has('nvim-0.10') == 1 then
        vim.health.ok('Neovim 0.10+ detected')
    else
        vim.health.warn('Neovim 0.10+ is recommended', {
            'The plugin relies on extmarks and modern treesitter APIs.',
        })
    end

    if vim.treesitter.language.add then
        vim.health.ok('Treesitter language API is available')
    else
        vim.health.warn('Treesitter language API looks limited', {
            'Mermaid fence detection may not work as expected on older Neovim versions.',
        })
    end

    vim.health.start('render-markdown-mermaid.nvim [tree-sitter]')

    if has_parser('markdown') then
        vim.health.ok('markdown treesitter parser is available')
    else
        vim.health.error('markdown treesitter parser is missing', {
            'Install the markdown parser with nvim-treesitter.',
        })
    end

    if has_parser('markdown_inline') then
        vim.health.ok('markdown_inline treesitter parser is available')
    else
        vim.health.error('markdown_inline treesitter parser is missing', {
            'Install the markdown_inline parser with nvim-treesitter.',
        })
    end

    vim.health.info('No separate mermaid treesitter parser is required; mermaid fences are detected from the markdown tree.')
end

return M
