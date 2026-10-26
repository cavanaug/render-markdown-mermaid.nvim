-- Buffer-local activation shortcut. Outside a diagram, delegate to an exact
-- copy of the previous mapping via a private Plug mapping. This lets Neovim
-- preserve callback/expr/remap behavior without running edits in textlock.
local scroll = require('render-markdown-mermaid.scroll')
local M = {}
local installed = {}
local attaching = {}
local focus_key = false

local function supported(buf)
    local ft = vim.bo[buf].filetype
    return ft == 'markdown' or ft == 'mdx' or ft == 'markdown.mdx'
end

function M.detach(buf)
    local mapping = installed[buf]
    installed[buf] = nil
    if not mapping or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end
    attaching[buf] = true
    vim.api.nvim_buf_call(buf, function()
        local current = vim.fn.maparg(mapping.key, 'n', false, true)
        if current.buffer == 1 and current.callback == mapping.callback then
            vim.keymap.del('n', mapping.key, { buffer = buf })
            if mapping.saved.buffer == 1 then
                vim.fn.mapset('n', false, mapping.saved)
            end
        end
        if mapping.alias then
            pcall(vim.keymap.del, 'n', mapping.alias, { buffer = buf })
        end
    end)
    attaching[buf] = nil
end

function M.attach(buf)
    if attaching[buf] or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end
    if not focus_key or not supported(buf) then
        M.detach(buf)
        return
    end
    -- Re-entering the buffer must not take back a key replaced by the user.
    if installed[buf] then return end
    attaching[buf] = true
    vim.api.nvim_buf_call(buf, function()
        local key = focus_key
        local saved = vim.fn.maparg(key, 'n', false, true)
        local alias = nil
        if next(saved) then
            alias = ('<Plug>(RenderMarkdownMermaidFallback%d)'):format(buf)
            local fallback = vim.deepcopy(saved)
            fallback.lhs = alias
            fallback.lhsraw = vim.api.nvim_replace_termcodes(alias, true, true, true)
            fallback.lhsrawalt = nil
            fallback.buffer = 1
            vim.fn.mapset('n', false, fallback)
        end
        local callback = function()
            if scroll.can_focus(buf) then return '<Cmd>MermaidFocus<CR>' end
            return alias or key
        end
        vim.keymap.set('n', key, callback, {
            buffer = buf, expr = true, desc = 'Navigate Mermaid diagram (otherwise normal key behavior)',
        })
        installed[buf] = { key = key, saved = saved, alias = alias, callback = callback }
    end)
    attaching[buf] = nil
end

function M.setup(key, group)
    focus_key = false
    for buf in pairs(installed) do M.detach(buf) end
    focus_key = key
    vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
        group = group,
        callback = function(args) M.attach(args.buf) end,
    })
    vim.api.nvim_create_autocmd({ 'BufUnload', 'BufDelete', 'BufWipeout' }, {
        group = group,
        callback = function(args) M.detach(args.buf) end,
    })
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do M.attach(buf) end
end

return M
