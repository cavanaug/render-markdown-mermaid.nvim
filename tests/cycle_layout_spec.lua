-- Real-screen test: nvim -u NONE -c 'luafile tests/cycle_layout_spec.lua'
-- Optional MERMAID_TEST_RESULT writes a JSON verdict for terminal automation.
-- MERMAID_TEST_SCROLLOFF also exercises a nonzero source-window margin.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require('render-markdown-mermaid.config')
config.available_renderers = function() return { selkie = true, bm = true, termaid = true } end
local pending = {}
local counts = { selkie = 24, bm = 3, termaid = 12 }
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(opts, source, _, callback)
        local label = source:find('Forward', 1, true) and 'second'
            or source:find('Think', 1, true) and 'third'
            or source:find('John', 1, true) and 'fourth' or 'first'
        local lines = {}
        for row = 1, counts[opts.cmd[1]] do
            lines[row] = ('%s %s row %03d'):format(opts.cmd[1], label, row)
        end
        pending[#pending + 1] = { callback = callback, lines = lines, label = label }
    end,
}
local plugin = require('render-markdown-mermaid')
local display = require('render-markdown-mermaid.display')
local function settle()
    vim.wait(30, function() return false end, 5)
    vim.cmd('redraw')
end
local function screenline(row)
    local text = ''
    for col = 1, vim.o.columns do text = text .. vim.fn.screenstring(row, col) end
    return text
end
local function run()
    vim.opt.number = true
    vim.opt.scrolloff = tonumber(vim.env.MERMAID_TEST_SCROLLOFF) or 0
    local sample = vim.fn.readfile('tests/fixtures/sequence_diagrams.md')
    for _, options in ipairs({ {}, { placement = 'below' }, { replace = true }, { hide_source = true } }) do
        for _, target in ipairs({ { 4, 'first' }, { 12, 'second' }, { 22, 'third' }, { 30, 'fourth' } }) do
            local buf = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_set_current_buf(buf)
            vim.bo[buf].filetype = 'markdown'
            vim.wo.conceallevel = 2
            vim.wo.concealcursor = 'nc'
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, sample)
            vim.treesitter.start(buf, 'markdown')
            vim.api.nvim_win_set_cursor(0, { target[1], 0 })
            require('render-markdown-mermaid.cache').values = {}
            plugin.setup(vim.tbl_extend('force', {
                auto_setup_render_markdown = false, debounce = 0, max_preview_lines = '75%',
            }, options))
            local function deliver(label)
                local remaining = {}
                for _, request in ipairs(pending) do
                    if not label or request.label == label then
                        request.callback({ ok = true, output = request.lines })
                    else
                        remaining[#remaining + 1] = request
                    end
                end
                pending = remaining
                settle()
            end
            local function check(label)
                local win = vim.api.nvim_get_current_win()
                assert(vim.api.nvim_get_current_buf() ~= buf, label .. ': viewer must be open')
                local pos = vim.api.nvim_win_get_position(win)
                local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                local view = vim.fn.winsaveview()
                assert(lines[1] == ('%s %s row 001'):format(plugin.config.cmd[1], target[2]),
                    label .. ': viewer must retain the selected fence')
                assert(screenline(pos[1]):find('Tab: next engine', 1, true),
                    label .. ': viewer must start immediately below its header; found ' .. screenline(pos[1]))
                for row = 1, vim.api.nvim_win_get_height(win) do
                    local expected = lines[view.topline + row - 1] or ''
                    assert(screenline(pos[1] + row):find(expected, 1, true), label .. ': viewer row mismatch')
                end
                local incremental = {}
                for row = 1, vim.o.lines - 2 do incremental[row] = screenline(row) end
                vim.cmd('redraw!')
                for row, text in ipairs(incremental) do
                    assert(screenline(row) == text, label .. ': stale screen row ' .. row
                        .. '\nbefore: ' .. text .. '\nafter: ' .. screenline(row))
                end
            end
            settle()
            deliver()
            -- Set the test cursor without scrolloff moving it past a tall
            -- preview, then restore the margin that focus must preserve.
            vim.wo.scrolloff = 0
            vim.api.nvim_win_set_cursor(0, { target[1], 0 })
            vim.wo.scrolloff = tonumber(vim.env.MERMAID_TEST_SCROLLOFF) or 0
            assert(require('render-markdown-mermaid.scroll').can_focus(buf),
                'target must be focusable before entry: ' .. vim.inspect(vim.api.nvim_win_get_cursor(0)))
            vim.cmd('MermaidFocus')
            settle()
            check('initial ' .. target[2] .. vim.inspect(options))
            for _, engine in ipairs({ 'bm', 'termaid', 'selkie' }) do
                local viewer = vim.api.nvim_get_current_win()
                local before = {}
                for row = 1, vim.o.lines - 2 do before[row] = screenline(row) end
                vim.cmd('MermaidCycle')
                settle()
                assert(vim.api.nvim_get_current_win() == viewer, 'switching must retain the viewer window')
                if engine ~= 'selkie' then
                    for row, text in ipairs(before) do
                        assert(screenline(row) == text, engine .. ' pending ' .. target[2] .. vim.inspect(options)
                            .. ' must not change screen row ' .. row .. '\nbefore: ' .. text .. '\nafter: ' .. screenline(row))
                    end
                end
                -- Finish the target before other diagrams to exercise their
                -- changing heights behind the same continuously focused viewer.
                deliver(target[2])
                check(engine .. ' target ready ' .. target[2] .. vim.inspect(options))
                deliver()
                check(engine .. ' all ready ' .. target[2] .. vim.inspect(options))
            end
            vim.cmd('MermaidFocus')
            settle()
            assert(vim.wo.scrolloff == (tonumber(vim.env.MERMAID_TEST_SCROLLOFF) or 0),
                'leaving focus must restore source scrolloff')
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end
vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
        vim.schedule(function()
            local ok, err = xpcall(run, debug.traceback)
            local message = ok and 'cycling layout: all checks passed' or ('FAIL: ' .. err)
            if vim.env.MERMAID_TEST_RESULT then
                vim.fn.writefile({ vim.json.encode({ ok = ok, message = message }) }, vim.env.MERMAID_TEST_RESULT)
            end
            print(message)
        end)
    end,
})
