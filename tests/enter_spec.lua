-- Run from the repo root: nvim --headless -u NONE -l tests/enter_spec.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local output = {}
for row = 1, 30 do output[row] = ('diagram row %02d'):format(row) end
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(_, _, _, callback)
        vim.schedule(function() callback({ ok = true, output = output }) end)
    end,
}
local plugin = require('render-markdown-mermaid')
local display = require('render-markdown-mermaid.display')
local function equal(actual, expected, message)
    assert(vim.deep_equal(actual, expected), message .. '\nactual: ' .. vim.inspect(actual))
end
local function keys(input)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(input, true, false, true), 'xt', false)
    vim.cmd('redraw')
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
end
local function setup(opts)
    plugin.setup(vim.tbl_extend('force', {
        auto_setup_render_markdown = false, debounce = 0, max_preview_lines = 8, center = false,
    }, opts or {}))
end
local function new_buffer(ft)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = ft or 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '# Test', '', '```mermaid', 'flowchart TD', 'A --> B', '```', '', 'After diagram',
    })
    return buf
end
local function ready(buf)
    assert(vim.wait(2000, function()
        local marks = vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, { details = true })
        for _, mark in ipairs(marks) do
            for _, line in ipairs(mark[4].virt_lines or {}) do
                if line[1][1] == output[1] then return true end
            end
        end
        return false
    end, 5), 'diagram did not render')
end

local function run()
    local buf = new_buffer()
    setup()
    ready(buf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    keys('<CR>')
    equal(vim.api.nvim_get_current_buf(), buf, 'Enter outside a diagram must stay in Markdown')
    equal(vim.api.nvim_win_get_cursor(0)[1], 2, 'unmapped Enter must keep its native movement')
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    keys('<CR>')
    assert(vim.api.nvim_get_current_buf() ~= buf, 'Enter on a Mermaid fence must open diagram navigation')
    equal(vim.api.nvim_get_current_line(), output[1], 'Enter must put the cursor in rendered output')
    keys('3j<CR>')
    equal(vim.api.nvim_win_get_cursor(0)[1], 5, 'Enter in the diagram must remain a native motion')
    keys('q')
    equal(vim.api.nvim_get_current_buf(), buf, 'q must return to Markdown')
    equal(vim.api.nvim_win_get_cursor(0)[1], 4, 'exit must restore the source cursor')

    -- A pre-existing Lua Enter mapping must execute outside textlock, including
    -- callbacks that edit the buffer, and remain untouched when disabled.
    setup({ focus_key = false })
    local calls = 0
    local callback = function()
        calls = calls + 1
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# Callback' })
    end
    vim.keymap.set('n', '<CR>', callback, { buffer = buf })
    setup()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    keys('<CR>')
    equal(calls, 1, 'existing Lua mappings must still execute outside diagrams')
    equal(vim.api.nvim_get_current_line(), '# Callback', 'existing callbacks must be allowed to edit text')
    display.render(buf, plugin.config)
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    keys('<CR>')
    assert(vim.api.nvim_get_current_buf() ~= buf, 'diagram Enter must take precedence only on a diagram')
    equal(calls, 1, 'opening a diagram must not invoke the fallback')
    keys('<Esc>')
    setup({ focus_key = false })
    equal(vim.fn.maparg('<CR>', 'n', false, true).callback, callback, 'disabling must restore the original buffer mapping')
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
        assert(not mapping.lhs:find('RenderMarkdownMermaidFallback', 1, true), 'disabling must remove fallback aliases')
    end
    vim.keymap.del('n', '<CR>', { buffer = buf })

    local expr_callback = function() return '<Down>' end
    vim.keymap.set('n', '<CR>', expr_callback, { buffer = buf, expr = true })
    setup()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    keys('<CR>')
    equal(vim.api.nvim_win_get_cursor(0)[1], 2, 'Lua expression fallback must preserve keycode expansion')
    setup({ focus_key = false })
    equal(vim.fn.maparg('<CR>', 'n', false, true).callback, expr_callback, 'disabling must restore Lua expression mappings')
    vim.keymap.del('n', '<CR>', { buffer = buf })

    -- Global mappings and expression mappings must retain native count handling.
    vim.keymap.set('n', '<CR>', '"j"', { expr = true })
    setup()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    keys('2<CR>')
    equal(vim.api.nvim_win_get_cursor(0)[1], 3, 'global expression fallback must preserve counts')
    setup({ focus_key = false })
    local restored = vim.fn.maparg('<CR>', 'n', false, true)
    equal(restored.buffer, 0, 'disabling must reveal the global mapping, not copy it into the source buffer')
    equal(restored.rhs, '"j"', 'the global expression mapping must remain unchanged')
    vim.keymap.del('n', '<CR>')

    -- String rhs mappings must preserve remapping through their own Plug target.
    local rhs_calls = 0
    vim.keymap.set('n', '<Plug>(TestEnter)', function() rhs_calls = rhs_calls + 1 end, { buffer = buf })
    vim.keymap.set('n', '<CR>', '<Plug>(TestEnter)', { buffer = buf, remap = true })
    setup()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    keys('<CR>')
    equal(rhs_calls, 1, 'rhs fallback must preserve remapping')

    -- Do not take back a mapping replaced by the user after setup.
    local replacement = function() end
    vim.keymap.set('n', '<CR>', replacement, { buffer = buf })
    vim.api.nvim_exec_autocmds('BufEnter', { buffer = buf })
    equal(vim.fn.maparg('<CR>', 'n', false, true).callback, replacement, 'buffer entry must respect a newer user mapping')
    setup({ focus_key = false })
    equal(vim.fn.maparg('<CR>', 'n', false, true).callback, replacement, 'cleanup must not discard a newer user mapping')
    vim.keymap.del('n', '<CR>', { buffer = buf })

    -- Replaced fences can be activated from the real line anchoring the preview.
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    setup({ replace = true })
    display.render(buf, plugin.config)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    keys('<CR>')
    assert(vim.api.nvim_get_current_buf() ~= buf, 'Enter at a replaced preview anchor must open it')
    equal(vim.api.nvim_win_get_config(0).bufpos, { 1, 0 }, 'viewer must stay over the replaced preview')
    display.render(buf, plugin.config)
    keys('Gq')
    equal(vim.api.nvim_get_current_buf(), buf, 'replaced preview must close normally')
    equal(vim.api.nvim_win_get_cursor(0)[1], 2, 'replaced preview must restore its original anchor cursor')

    -- Configurable shortcut and newly opened Markdown/MDX buffers.
    setup({ focus_key = '<Tab>' })
    display.render(buf, plugin.config)
    equal(vim.fn.maparg('<CR>', 'n', false, true).buffer, nil, 'changing shortcuts must remove the old Enter mapping')
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    keys('<Tab>')
    assert(vim.api.nvim_get_current_buf() ~= buf, 'a configured shortcut must open navigation')
    keys('q')
    setup()
    local mdx = new_buffer('mdx')
    display.render(mdx, plugin.config)
    ready(mdx)
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    keys('<CR>')
    assert(vim.api.nvim_get_current_buf() ~= mdx, 'new MDX buffers must get the shortcut')
    keys('q')
    vim.bo[mdx].filetype = 'lua'
    equal(vim.fn.maparg('<CR>', 'n', false, true).buffer, nil, 'changing to an unsupported filetype must restore Enter')
    local config = require('render-markdown-mermaid.config')
    for _, invalid in ipairs({ '', 0, true }) do
        equal(config.merge({ focus_key = invalid }).focus_key, '<CR>', 'invalid focus_key must fall back to Enter')
    end
    print('diagram Enter shortcut: all checks passed')
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
else
    vim.cmd('qa!')
end
