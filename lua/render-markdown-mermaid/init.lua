local config_mod = require('render-markdown-mermaid.config')
local integration = require('render-markdown-mermaid.integration')

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
    opts.custom_handlers = opts.custom_handlers or {}
    opts.custom_handlers.markdown = integration.handler(M.config)
    render_markdown.setup(opts)
end

---@param opts? table
function M.setup(opts)
    M.config = config_mod.merge(opts)

    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidPending', { link = 'DiagnosticInfo' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidError', { link = 'DiagnosticWarn' })

    vim.api.nvim_create_autocmd('User', {
        group = vim.api.nvim_create_augroup('RenderMarkdownMermaid', { clear = true }),
        callback = function(args)
            if not (args.data and args.data.render_markdown_mermaid) then
                return
            end
            local ok, render_markdown = pcall(require, 'render-markdown')
            if ok and render_markdown and render_markdown.set_buf then
                local current = vim.api.nvim_get_current_buf()
                if args.buf and args.buf ~= 0 then
                    vim.api.nvim_set_current_buf(args.buf)
                end
                pcall(render_markdown.set_buf, true)
                if vim.api.nvim_buf_is_valid(current) and current ~= vim.api.nvim_get_current_buf() then
                    vim.api.nvim_set_current_buf(current)
                end
            end
        end,
    })

    setup_render_markdown()
end

---@return render.md.Handler
function M.handler()
    if not M.config then
        M.setup({})
    end
    return integration.handler(M.config)
end

return M
