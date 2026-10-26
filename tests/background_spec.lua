-- Real-screen regression test (not headless):
-- nvim -u NONE -c 'luafile tests/background_spec.lua'
-- Optional MERMAID_TEST_RESULT writes the verdict for terminal automation.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local result_path = vim.env.MERMAID_TEST_RESULT
local output = { 'diagram', 'x', '' }
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(_, _, _, callback)
        vim.schedule(function() callback({ ok = true, output = output }) end)
    end,
}
local function run()
    vim.opt.termguicolors = true
    vim.api.nvim_set_hl(0, 'Normal', { fg = '#ffffff', bg = '#000000' })
    vim.api.nvim_set_hl(0, 'RenderMarkdownCode', { fg = '#ffffff', bg = '#303030' })
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '# Test', '', '```mermaid', 'graph TD', 'A --> B', '```', '', 'After',
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    local plugin = require('render-markdown-mermaid')
    plugin.setup({ auto_setup_render_markdown = false, debounce = 0 })
    local display = require('render-markdown-mermaid.display')
    assert(vim.wait(1000, function()
        return #vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, {}) > 0
            and require('render-markdown-mermaid.scroll').can_focus(buf)
    end, 5), 'output did not render')
    local function check_background(label, win)
        win = win or vim.api.nvim_get_current_win()
        vim.cmd('redraw!')
        local info = vim.fn.getwininfo(win)[1]
        local left = info.wincol + info.textoff
        local right = info.wincol + info.width - 1
        local row, column
        for r = info.winrow, info.winrow + info.height - 1 do
            local text = ''
            for c = left, right do text = text .. vim.fn.screenstring(r, c) end
            local found = text:find('diagram', 1, true)
            if found then row, column = r, left + found - 1; break end
        end
        assert(row, label .. ': rendered text is not visible')
        local text_attr = vim.fn.screenattr(row, column)
        local right_attr = vim.fn.screenattr(row, right)
        assert(text_attr ~= 0, 'screen attributes must be available')
        assert(right_attr == text_attr, ('%s: background changes at end of rendered text (text attr=%d, right-edge attr=%d)')
            :format(label, text_attr, right_attr))
        assert(vim.fn.screenattr(row + 1, right) == text_attr, label .. ': short rows must fill to the right edge')
        assert(vim.fn.screenattr(row + 2, right) == text_attr, label .. ': empty rows must fill to the right edge')
    end
    local source_win = vim.api.nvim_get_current_win()
    check_background('centered inline preview')
    vim.cmd('MermaidFocus')
    check_background('centered focused preview')
    check_background('centered focused preview through source right edge', source_win)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), output), 'background fill must not alter copied output')
    vim.cmd('MermaidFocus')
    plugin.config.center = false
    display.render(buf, plugin.config)
    check_background('left-aligned inline preview')
    vim.cmd('MermaidFocus')
    check_background('left-aligned focused preview')
    check_background('left-aligned focused preview through source right edge', source_win)
    vim.cmd('MermaidFocus')

    local original = vim.api.nvim_get_current_win()
    vim.cmd('belowright 24vsplit')
    local small = vim.api.nvim_get_current_win()
    vim.wo.number = true
    display.render(buf, plugin.config)
    check_background('numbered narrow split', small)
    check_background('wide split', original)
    plugin.config.center = true
    display.render(buf, plugin.config)
    check_background('centered numbered narrow split', small)
    check_background('centered wide split', original)
    vim.api.nvim_win_close(small, true)
    display.render(buf, plugin.config)
    check_background('full width after split closes')
end

vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
        vim.schedule(function()
            local ok, err = xpcall(run, debug.traceback)
            local message = ok and 'background consistency: all checks passed' or ('FAIL: ' .. err)
            if result_path then vim.fn.writefile({ vim.json.encode({ ok = ok, message = message }) }, result_path) end
            print(message)
        end)
    end,
})
