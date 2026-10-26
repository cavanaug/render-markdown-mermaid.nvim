-- Run from the repo root: nvim --headless -u NONE -l tests/center_spec.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local output = { '┌───┐', '│中 │', '└───┘' }
local requests = 0
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(_, _, _, callback)
        requests = requests + 1
        vim.schedule(function() callback({ ok = true, output = output }) end)
    end,
}
local plugin = require('render-markdown-mermaid')
local display = require('render-markdown-mermaid.display')
local function equal(actual, expected, message)
    assert(vim.deep_equal(actual, expected), message .. ': ' .. vim.inspect(actual))
end
local function rendered(buf)
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, { details = true })) do
        if mark[4].virt_lines then return mark[4].virt_lines end
    end
    return {}
end
local function setup(opts)
    plugin.setup(vim.tbl_extend('force', { auto_setup_render_markdown = false, debounce = 0 }, opts or {}))
end
local function run()
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].filetype = 'markdown'
    vim.wo.number = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# Test', '```mermaid', 'graph TD', 'A --> B', '```' })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    setup()
    assert(vim.wait(1000, function() return #rendered(buf) == 3 end, 5), 'diagram never rendered')
    equal(plugin.config.center, true, 'centering must be enabled by default')
    local source = vim.api.nvim_get_current_win()
    local width = vim.api.nvim_win_get_width(source) - vim.fn.getwininfo(source)[1].textoff
    local pad = math.floor((width - 5) / 2)
    equal(rendered(buf)[1][1][1], string.rep(' ', pad) .. output[1], 'Unicode display cells and number columns must determine centering')
    equal(rendered(buf)[2][1][1], string.rep(' ', pad) .. output[2], 'all rows must get the same padding to preserve geometry')
    local request_count = requests
    vim.cmd('MermaidFocus')
    equal(vim.api.nvim_win_get_config(0).col, pad, 'focused window must align with centered virtual lines')
    equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), output, 'centering must not pad cached/rendered buffer text')
    equal(requests, request_count, 'centering/focus must not rerun the renderer')
    plugin.config.center = false
    display.render(buf, plugin.config)
    equal(vim.api.nvim_win_get_config(0).col, 0, 'layout changes must realign an already focused window')
    plugin.config.center = true
    display.render(buf, plugin.config)
    equal(vim.api.nvim_win_get_config(0).col, pad, 'focused window must recenter without reopening')
    vim.cmd('MermaidFocus')
    vim.cmd('belowright 20vsplit')
    local small = vim.api.nvim_get_current_win()
    display.render(buf, plugin.config)
    local small_width = vim.api.nvim_win_get_width(small) - vim.fn.getwininfo(small)[1].textoff
    equal(rendered(buf)[1][1][1], string.rep(' ', math.max(0, math.floor((small_width - 5) / 2))) .. output[1],
        'shared virtual lines must center within the smallest source window')
    vim.api.nvim_win_close(small, true)
    setup({ center = false })
    display.render(buf, plugin.config)
    equal(rendered(buf)[1][1][1], output[1], 'center=false must restore left alignment')
    vim.cmd('MermaidFocus')
    equal(vim.api.nvim_win_get_config(0).col, 0, 'left-aligned focus must stay left-aligned')
    vim.cmd('MermaidFocus')

    -- Use the widest row of the full output, not just the current page.
    output = {}
    for i = 1, 30 do output[i] = i == 30 and string.rep('x', width + 20) or 'narrow' end
    vim.api.nvim_buf_set_lines(buf, 3, 4, false, { 'A --> Wide' })
    setup({ max_preview_lines = 5 })
    display.render(buf, plugin.config)
    assert(vim.wait(1000, function()
        local lines = rendered(buf)
        return lines[2] and lines[2][1][1] == 'narrow'
    end, 5), 'wide diagram must not receive padding even when its widest row is offscreen')
    vim.cmd('MermaidFocus')
    equal(vim.api.nvim_win_get_config(0).col, 0, 'overflow must stay left-aligned for horizontal scrolling')
    vim.cmd('MermaidFocus')
    print('diagram centering: all checks passed')
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
else
    vim.cmd('qa!')
end
