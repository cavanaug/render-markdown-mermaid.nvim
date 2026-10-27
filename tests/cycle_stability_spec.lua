-- Run from the repo root: nvim --headless -u NONE -l tests/cycle_stability_spec.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require('render-markdown-mermaid.config')
config.available_renderers = function() return { selkie = true, bm = true, termaid = true } end
local pending = {}
local counts = { selkie = 18, bm = 3, termaid = 24 }
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(opts, source, _, callback)
        local lines = {}
        for row = 1, counts[opts.cmd[1]] do lines[row] = opts.cmd[1] .. ' ' .. source .. ' row ' .. row end
        local result = { ok = true, output = lines }
        if opts.cmd[1] == 'selkie' then
            vim.schedule(function() callback(result) end)
        else
            pending[#pending + 1] = { callback = callback, result = result }
        end
    end,
}
local plugin = require('render-markdown-mermaid')
local display = require('render-markdown-mermaid.display')
local scroll = require('render-markdown-mermaid.scroll')
local function equal(actual, expected, message)
    assert(vim.deep_equal(actual, expected), message .. '\nactual: ' .. vim.inspect(actual))
end
local function keys(input)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(input, true, false, true), 'xt', false)
end
local function preview(buf)
    local lines = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, { details = true })) do
        for _, line in ipairs(mark[4].virt_lines or {}) do lines[#lines + 1] = line end
    end
    return lines
end
local function run()
    local source = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()
    vim.bo[source].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(source, 0, -1, false, {
        '# Test', '', '```mermaid', 'First', '```', '',
        '# Second', '', '```mermaid', 'Second', '```', '', 'After diagrams',
    })
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    plugin.setup({ auto_setup_render_markdown = false, debounce = 0, max_preview_lines = 10, center = false })
    assert(vim.wait(1000, function() return scroll.can_focus(source) end, 5), 'initial output must render')
    keys('<CR>')
    local viewer = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    assert(viewer ~= source, 'test must focus a diagram')
    local cursor = vim.api.nvim_win_get_cursor(source_win)
    local view = vim.api.nvim_win_call(source_win, vim.fn.winsaveview)
    local inline = preview(source)
    local position = vim.api.nvim_win_get_position(win)
    local leaves = 0
    vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
        callback = function() leaves = leaves + 1 end,
    })
    keys('<Tab>')
    equal(vim.api.nvim_get_current_win(), win, 'cycling must not close the viewer and reveal the source')
    equal(vim.api.nvim_get_current_buf(), viewer, 'cycling must reuse the same scratch buffer')
    assert(vim.wait(1000, function() return #pending == 2 end, 5), 'both new renders must be pending')
    equal(vim.api.nvim_win_get_cursor(source_win), cursor, 'cycling must not restore the source cursor mid-switch')
    equal(vim.api.nvim_win_call(source_win, vim.fn.winsaveview), view, 'pending output must not move the source view')
    equal(preview(source), inline, 'pending renders must retain all previous preview rows')
    equal(leaves, 0, 'cycling must not emit source/viewer leave events')
    pending[1].callback(pending[1].result)
    assert(vim.wait(1000, function()
        return vim.inspect(preview(source)):find('bm First row 1', 1, true) ~= nil
    end, 5), 'the other fence must complete before the active fence')
    equal(vim.api.nvim_win_get_position(win), position, 'another fence changing height must not move the viewer')
    equal(vim.api.nvim_buf_get_lines(viewer, 0, 1, false)[1], 'selkie Second row 1', 'pending active output must stay visible')
    pending[2].callback(pending[2].result)
    assert(vim.wait(1000, function() return vim.api.nvim_buf_get_lines(viewer, 0, 1, false)[1] == 'bm Second row 1' end, 5),
        'new output must replace the old output in place')
    equal(vim.api.nvim_get_current_win(), win, 'new output must keep the same viewer window')
    equal(vim.api.nvim_get_current_buf(), viewer, 'new output must keep the same viewer buffer')
    equal(vim.api.nvim_buf_line_count(viewer), 3, 'shorter output must remove old rows')
    equal(vim.api.nvim_win_get_position(win), position, 'shorter output must preserve the viewer origin')
    equal(vim.bo[viewer].readonly, true, 'in-place replacement must restore readonly')
    equal(vim.bo[viewer].modifiable, false, 'in-place replacement must restore nonmodifiable')
    equal(leaves, 0, 'ready output must not switch windows or buffers')

    -- Repeated Tab remains available even before the next backend finishes.
    pending = {}
    keys('<Tab>')
    assert(vim.wait(1000, function() return #pending == 2 end, 5), 'the next backend must still be pending')
    keys('<Tab>')
    assert(vim.wait(1000, function() return vim.api.nvim_buf_get_lines(viewer, 0, 1, false)[1] == 'selkie Second row 1' end, 5),
        'rapid Tab must cycle past a slow renderer into cached output')
    for _, request in ipairs(pending) do request.callback(request.result) end
    vim.wait(30, function() return false end, 5)
    equal(vim.api.nvim_buf_get_lines(viewer, 0, 1, false)[1], 'selkie Second row 1', 'late skipped output must not overwrite the viewer')
    keys('<S-Tab>')
    assert(vim.wait(1000, function() return vim.api.nvim_buf_line_count(viewer) == 24 end, 5), 'longer cached output must replace the same buffer')
    equal(vim.api.nvim_win_get_position(win), position, 'longer output must preserve the viewer origin')
    equal(leaves, 0, 'rapid/reverse cycling must not leave the viewer')

    -- Explicit exit during a slow switch must not reopen on a late callback.
    plugin.config.cli.padding_x = 73
    pending = {}
    keys('<S-Tab>')
    assert(vim.wait(1000, function() return #pending == 2 end, 5), 'exit test must hold a fresh render')
    keys('q')
    equal(vim.api.nvim_get_current_win(), source_win, 'explicit exit must return to the source')
    equal(vim.api.nvim_win_get_cursor(source_win), { 10, 0 }, 'exit must restore the original source cursor')
    for _, request in ipairs(pending) do request.callback(request.result) end
    vim.wait(30, function() return false end, 5)
    equal(vim.api.nvim_get_current_win(), source_win, 'a late callback must not reopen an explicitly closed viewer')
    print('stable renderer cycling: all checks passed')
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
else
    vim.cmd('qa!')
end
