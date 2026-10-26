-- Run from the repo root: nvim --headless -u NONE -l tests/preview_height_spec.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local output = {}
for row = 1, 100 do output[row] = ('row %03d'):format(row) end
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(_, _, _, callback)
        vim.schedule(function() callback({ ok = true, output = output }) end)
    end,
}
local config = require('render-markdown-mermaid.config')
local display = require('render-markdown-mermaid.display')
local function equal(actual, expected, message)
    assert(actual == expected, message .. ': ' .. vim.inspect(actual))
end
local function run()
    equal(config.merge().max_preview_lines, '75%', 'default must be 75 percent')
    for _, valid in ipairs({ '1%', '50%', '75%', '100%', '62.5%' }) do
        equal(config.merge({ max_preview_lines = valid }).max_preview_lines, valid, 'valid percentage must be preserved')
    end
    for _, invalid in ipairs({ '0%', '101%', '-5%', 'nan%', '75', '', 0, -1, math.huge }) do
        equal(config.merge({ max_preview_lines = invalid }).max_preview_lines, '75%', 'invalid limit must use the default')
    end
    equal(config.merge({ max_preview_lines = 'auto' }).max_preview_lines, '75%', 'legacy auto must resolve to the new default')
    equal(config.merge({ max_preview_lines = 8 }).max_preview_lines, 8, 'legacy row limits must keep working')
    equal(config.merge({ max_preview_lines = false }).max_preview_lines, false, 'false must still mean unlimited')

    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '```mermaid', 'graph TD', 'A --> B', '```' })
    local opts = config.merge({ max_preview_lines = '75%', center = false })
    local function rows()
        local count = 0
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, { details = true })) do
            for _, line in ipairs(mark[4].virt_lines or {}) do
                if line[1][1]:match('^row %d+') then count = count + 1 end
            end
        end
        return count
    end
    local function expected(height, percent)
        return math.max(1, math.min(math.floor(height * percent / 100), height - 4))
    end
    display.render(buf, opts)
    assert(vim.wait(1000, function() return rows() > 0 end, 5), 'output never rendered')
    equal(rows(), expected(vim.api.nvim_win_get_height(0), 75), 'initial viewport must use 75 percent')

    vim.cmd('belowright 12split')
    local smallest = math.huge
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        smallest = math.min(smallest, vim.api.nvim_win_get_height(win))
    end
    display.render(buf, opts)
    equal(rows(), expected(smallest, 75), 'percentage must recalculate and leave space for the header/anchor')
    opts.max_preview_lines = '50%'
    display.render(buf, opts)
    equal(rows(), expected(smallest, 50), 'custom percentage must use the smallest source window')
    opts.max_preview_lines = '62.5%'
    display.render(buf, opts)
    equal(rows(), expected(smallest, 62.5), 'fractional percentages must round down to whole rows')
    opts.max_preview_lines = '100%'
    display.render(buf, opts)
    equal(rows(), expected(smallest, 100), '100 percent must still leave room for navigation chrome')
    opts.max_preview_lines = '1%'
    display.render(buf, opts)
    equal(rows(), 1, 'a tiny percentage must show at least one row')
    print('percentage preview height: all checks passed')
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
else
    vim.cmd('qa!')
end
