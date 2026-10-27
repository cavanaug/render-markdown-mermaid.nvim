-- Run from the repo root: nvim --headless -u NONE -l tests/cycle_height_spec.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require('render-markdown-mermaid.config')
config.available_renderers = function() return { selkie = true, bm = true, termaid = true } end
local counts = { selkie = 80, bm = 3, termaid = 30 }
local fail = false
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(opts, _, _, callback)
        local name = opts.cmd[1]
        local lines = {}
        for row = 1, counts[name] do lines[row] = ('%s row %03d'):format(name, row) end
        local result = fail and { ok = false, error = 'test failure' } or { ok = true, output = lines }
        vim.schedule(function() callback(result) end)
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
local function run()
    local buf = vim.api.nvim_get_current_buf()
    vim.wo.scrolloff = 7
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '# Test', '', '```mermaid', 'flowchart TD', 'A --> B', '```', '', 'After diagram',
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    plugin.setup({ auto_setup_render_markdown = false, debounce = 0, max_preview_lines = 10, center = false })
    local function wait_viewer(name)
        assert(vim.wait(1000, function()
            local current = vim.api.nvim_get_current_buf()
            return current ~= buf and vim.api.nvim_buf_get_lines(current, 0, 1, false)[1] == name .. ' row 001'
        end, 5), 'viewer must reopen with ' .. name)
        vim.cmd('redraw')
        equal(vim.api.nvim_buf_line_count(0), counts[name], 'viewer must contain only new output')
        equal(vim.api.nvim_win_get_height(0), math.min(counts[name], 10), 'viewer must resize to new output')
        local inline = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, { details = true })) do
            for _, line in ipairs(mark[4].virt_lines or {}) do inline[#inline + 1] = line[1][1] end
        end
        equal(#inline, math.min(counts[name], 10) + 1, 'inline height must match new viewer plus header')
        assert(table.concat(inline, '\n'):find('| ' .. name .. ' |', 1, true), 'header must identify new backend')
    end
    assert(vim.wait(1000, function()
        return #vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, {}) > 0
    end, 5), 'initial output must render')
    vim.cmd('MermaidFocus')
    wait_viewer('selkie')
    keys('G')
    equal(vim.api.nvim_win_get_cursor(0)[1], 80, 'test must scroll to old output bottom')
    keys('<Tab>')
    wait_viewer('bm')
    keys('<Tab>')
    wait_viewer('termaid')
    keys('G<S-Tab>')
    wait_viewer('bm')
    keys('<S-Tab>')
    wait_viewer('selkie')
    keys('q')
    equal(vim.api.nvim_get_current_buf(), buf, 'exit must return to Markdown')
    equal(vim.wo.scrolloff, 7, 'exit must restore source scrolloff')

    vim.cmd('MermaidFocus')
    plugin.config.cli.padding_x = 73
    fail = true
    keys('<Tab>')
    assert(vim.wait(1000, function()
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, { details = true })) do
            local lines = mark[4].virt_lines
            if lines and lines[1][1][1] == plugin.config.ui.error then return true end
        end
        return false
    end, 5), 'failed backend must show its error')
    equal(vim.api.nvim_get_current_buf(), buf, 'failed rendering must leave focus in Markdown')
    equal(vim.wo.scrolloff, 7, 'failed rendering must restore source scrolloff')
    print('renderer cycling heights: all checks passed')
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
else
    vim.cmd('qa!')
end
