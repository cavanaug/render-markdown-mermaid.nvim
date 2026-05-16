local M = {}

local function health()
    return vim.health or require('health')
end

local function has_executable(command)
    return vim.fn.executable(command) == 1
end

local function has_parser(language)
    return pcall(vim.treesitter.language.add, language)
end

function M.check()
    local ok, render_markdown = pcall(require, 'render-markdown')
    local config_ok, mermaid = pcall(require, 'render-markdown-mermaid')
    local report = health()
    local command = 'mermaid-ascii'
    if config_ok and mermaid and mermaid.config and mermaid.config.cmd and mermaid.config.cmd[1] then
        command = mermaid.config.cmd[1]
    end

    report.start('render-markdown-mermaid.nvim')

    if ok and render_markdown then
        report.ok('render-markdown.nvim is installed')
    else
        report.error('render-markdown.nvim is not available', {
            'Install MeanderingProgrammer/render-markdown.nvim.',
            'This plugin auto-configures render-markdown.nvim by default.',
        })
    end

    if has_executable(command) then
        report.ok(('renderer executable is available: %s'):format(command))
    else
        report.error(('renderer executable is not available in PATH: %s'):format(command), {
            'Install mermaid-ascii or configure setup({ cmd = { ... } }).',
            'The default command is: mermaid-ascii',
        })
    end

    if vim.fn.has('nvim-0.10') == 1 then
        report.ok('Neovim 0.10+ detected')
    else
        report.warn('Neovim 0.10+ is recommended', {
            'The plugin relies on extmarks and modern treesitter APIs.',
        })
    end

    if vim.treesitter.language.add then
        report.ok('Treesitter language API is available')
    else
        report.warn('Treesitter language API looks limited', {
            'Injected mermaid fences may not work as expected on older Neovim versions.',
        })
    end

    if has_parser('markdown') then
        report.ok('markdown treesitter parser is available')
    else
        report.error('markdown treesitter parser is missing', {
            'Install the markdown parser with nvim-treesitter.',
        })
    end

    if has_parser('markdown_inline') then
        report.ok('markdown_inline treesitter parser is available')
    else
        report.error('markdown_inline treesitter parser is missing', {
            'Install the markdown_inline parser with nvim-treesitter.',
        })
    end

    report.info('No separate mermaid treesitter parser is required; mermaid fences are detected from the markdown tree.')
end

return M
