-- Run from the repo root: nvim --headless -u NONE -l tests/cycle_repeat_spec.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require('render-markdown-mermaid.config')
config.available_renderers = function() return { selkie = true, bm = true, termaid = true } end
local counts = { selkie = 24, bm = 3, termaid = 12 }
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(opts, source, _, callback)
        local lines = {}
        local tag = source:find('TargetNode', 1, true) and 'target' or 'other'
        for row = 1, counts[opts.cmd[1]] do lines[row] = opts.cmd[1] .. ' row ' .. row .. ' ' .. tag end
        vim.defer_fn(function() callback({ ok = true, output = lines }) end, 20)
    end,
}
local plugin = require('render-markdown-mermaid')
local scroll = require('render-markdown-mermaid.scroll')
local function keys(input)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(input, true, false, true), 'xt', false)
end
local function run()
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].filetype = 'markdown'
    vim.wo.conceallevel = 2
    vim.wo.concealcursor = 'nc'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile('samples/sequence_diagrams.md'))
    vim.api.nvim_win_set_cursor(0, { 4, 5 })
    vim.treesitter.start(buf, 'markdown')
    plugin.setup({ auto_setup_render_markdown = false, debounce = 0, replace = true })
    assert(vim.wait(1000, function() return scroll.can_focus(buf) end, 5), 'first output must be ready')
    vim.wo.scrolloff = 0
    vim.api.nvim_win_set_cursor(0, { 4, 5 })
    vim.wo.scrolloff = 8
    keys('<CR>')
    assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() ~= buf end, 5), 'Enter must open viewer')
    for round = 1, 4 do
        for _, name in ipairs({ 'bm', 'termaid', 'selkie' }) do
            keys('<Tab>')
            assert(plugin.config.cmd[1] == name, 'Tab must select ' .. name .. ' on round ' .. round)
            if round == 1 then
                assert(vim.api.nvim_get_current_buf() == buf, 'test must restore the anchor while rendering is pending')
                -- A queued view restoration can park the source cursor back
                -- at its preview anchor after cycling restored the user view.
                vim.api.nvim_win_set_cursor(0, { 2, 0 })
                vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
            end
            assert(vim.wait(1000, function()
                return vim.api.nvim_get_current_buf() ~= buf
                    and vim.api.nvim_get_current_line():find(name, 1, true) ~= nil
            end, 5), 'viewer must reopen for ' .. name .. ' on round ' .. round)
            vim.wait(50, function() return false end, 5)
            assert(vim.api.nvim_get_current_buf() ~= buf, 'viewer must remain open after ' .. name)
        end
    end
    keys('q')
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 4, 5 }),
        'exiting after repeated cycles must restore the original source cursor, not its parked anchor')
    assert(vim.wo.scrolloff == 8, 'exiting must restore the source scrolloff')

    -- Adjacent fences share a boundary: the second preview's anchor lies
    -- inside the first fence. Re-entry must use fence identity, not lookup.
    local adjacent = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(adjacent)
    vim.bo[adjacent].filetype = 'markdown'
    vim.wo.scrolloff = 0
    vim.wo.conceallevel = 0
    vim.api.nvim_buf_set_lines(adjacent, 0, -1, false, {
        '```mermaid', 'graph TD', 'A --> OtherNode', '```',
        '```mermaid', 'graph TD', 'A --> TargetNode', '```', '', 'After diagrams',
    })
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    plugin.setup({ auto_setup_render_markdown = false, debounce = 0, cmd = { 'selkie' } })
    assert(vim.wait(1000, function() return scroll.can_focus(adjacent) end, 5), 'adjacent target must render')
    keys('<CR>')
    assert(vim.api.nvim_get_current_line():find('target', 1, true), 'test must focus the second fence')
    keys('<Tab>')
    assert(vim.api.nvim_get_current_buf() == adjacent, 'adjacent render must still be pending')
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = adjacent })
    assert(vim.wait(1000, function()
        return vim.api.nvim_get_current_buf() ~= adjacent and vim.api.nvim_get_current_line():find('bm', 1, true)
    end, 5), 'adjacent target must reopen after the anchor is restored')
    assert(vim.api.nvim_get_current_line():find('target', 1, true), 'cycling must not open the neighbouring fence')
    keys('q')
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 6, 0 }), 'adjacent cycle must preserve original source cursor')
    print('repeated Tab cycling: all checks passed')
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
else
    vim.cmd('qa!')
end
