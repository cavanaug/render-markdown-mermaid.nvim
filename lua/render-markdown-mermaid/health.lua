local M = {}
local config_mod = require('render-markdown-mermaid.config')

local function has_executable(command)
    return vim.fn.executable(command) == 1
end

local function has_parser(language)
    return pcall(vim.treesitter.language.add, language)
end

function M.check()
    local ok, render_markdown = pcall(require, 'render-markdown')
    local config_ok, mermaid = pcall(require, 'render-markdown-mermaid')
    local command = config_mod.resolve_cmd(config_ok and mermaid and mermaid.config and mermaid.config.cmd or nil)[1]

    vim.health.start('render-markdown-mermaid.nvim [dependencies]')

    if ok and render_markdown then
        vim.health.ok('render-markdown.nvim is installed')
    else
        vim.health.error('render-markdown.nvim is not available', {
            'Install MeanderingProgrammer/render-markdown.nvim.',
            'This plugin auto-configures render-markdown.nvim by default.',
        })
    end

    if has_executable(command) then
        vim.health.ok(('renderer executable is available: %s'):format(command))
    else
        vim.health.error(('renderer executable is not available in PATH: %s'):format(command), {
            'Install Beautiful Mermaid (bm, preferred) or mermaid-ascii, or configure setup({ cmd = { ... } }).',
            'The default renderer selection prefers bm and falls back to mermaid-ascii.',
        })
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
