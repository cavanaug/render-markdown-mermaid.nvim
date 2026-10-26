-- Run from the repo root: nvim --headless -u NONE -l tests/scroll_spec.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local requests = 0
local notice = nil
local output = {}
for row = 1, 100 do output[row] = ('diagram row %03d'):format(row) end
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(_, _, _, callback)
        requests = requests + 1
        vim.schedule(function() callback({ ok = true, output = vim.deepcopy(output), notice = notice }) end)
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
    -- In a headless -l invocation there is no interactive main-loop turn
    -- between assertions. Deliver the normal cursor event after native keys.
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
end
local function preview(buf)
    local lines = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, { details = true })) do
        for _, line in ipairs(mark[4].virt_lines or {}) do lines[#lines + 1] = line[1][1] end
    end
    return lines
end
local function wait_for(buf, text)
    assert(vim.wait(2000, function()
        return table.concat(preview(buf), '\n'):find(text, 1, true) ~= nil
    end, 5), 'preview never showed ' .. text)
end
local function new_buffer()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '# Test', '', '```mermaid', 'flowchart TD', 'A --> B', '```', '', 'After the diagram',
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    return buf
end
local function setup(opts)
    plugin.setup(vim.tbl_extend('force', {
        auto_setup_render_markdown = false, debounce = 0, max_preview_lines = 10, center = false,
    }, opts or {}))
end

local function run()
    local buf = new_buffer()
    local source_win = vim.api.nvim_get_current_win()
    local original_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local original_cursor = vim.api.nvim_win_get_cursor(source_win)
    local original_tick = vim.api.nvim_buf_get_changedtick(buf)
    local old_j = function() end
    vim.keymap.set('n', 'j', old_j, { buffer = buf, desc = 'User mapping' })
    setup()
    wait_for(buf, 'diagram row 001')
    equal(#preview(buf), 11, 'tall diagram must have ten rows plus an indicator')
    vim.cmd('MermaidFocus')
    local viewer = vim.api.nvim_get_current_buf()
    local float = vim.api.nvim_get_current_win()
    assert(viewer ~= buf, 'focus must put a real cursor in rendered output, not Markdown')
    equal(vim.api.nvim_buf_get_lines(viewer, 0, -1, false), output, 'viewer must contain every rendered row')
    equal(vim.api.nvim_win_get_config(float).win, source_win, 'viewer must overlay the inline source window')
    equal(vim.bo[viewer].modifiable, false, 'rendered output must be read-only')
    equal(vim.bo[viewer].buflisted, false, 'viewer must not pollute the buffer list')
    equal(vim.bo[viewer].buftype, 'nofile', 'viewer must be a scratch buffer, not a file')
    equal(vim.wo[float].wrap, false, 'wide diagram geometry must not wrap')
    equal(#vim.api.nvim_buf_get_keymap(viewer, 'n'), 4, 'only exit/backend-cycle keys may be mapped; motions must remain native')
    local anchor = vim.api.nvim_win_get_cursor(source_win)
    local request_count = requests

    keys('3j')
    equal(vim.api.nvim_win_get_cursor(float)[1], 4, '3j must move the real diagram cursor three lines')
    equal(preview(buf)[2], 'diagram row 001', 'cursor movement within the viewport must not scroll it')
    keys('w')
    equal(vim.api.nvim_win_get_cursor(float)[2], 8, 'word motion must operate on rendered text')
    keys('0f0')
    equal(vim.api.nvim_win_get_cursor(float)[2], 12, 'character-find motion must operate on rendered text')
    keys('Vy')
    equal(vim.fn.getreg('"'), 'diagram row 004\n', 'visual selection and yank must copy rendered output')
    keys('G')
    equal(vim.api.nvim_win_get_cursor(float)[1], 100, 'G must reach the last actual diagram line')
    equal(preview(buf)[11], 'diagram row 100', 'inline range must follow native window scrolling')
    keys('gg')
    equal(vim.api.nvim_win_get_cursor(float)[1], 1, 'gg must reach the first actual diagram line')
    keys('/row 050<CR>')
    equal(vim.api.nvim_win_get_cursor(float)[1], 50, 'native search must find rendered text')
    keys('/row 0[67]0<CR>n')
    equal(vim.api.nvim_win_get_cursor(float)[1], 70, 'native n must repeat the diagram search')
    keys('N')
    equal(vim.api.nvim_win_get_cursor(float)[1], 60, 'native N must repeat the search backwards')
    keys('<C-d>')
    assert(vim.fn.line('w0') > 50, 'native half-page scrolling must move the diagram window')
    equal(vim.api.nvim_win_get_cursor(source_win), anchor, 'diagram navigation must not move the source cursor')
    equal(requests, request_count, 'navigation must not invoke the backend again')
    local saved_cursor = vim.api.nvim_win_get_cursor(float)
    keys('<Esc>')
    equal(vim.api.nvim_get_current_win(), source_win, 'exit must return to the source window')
    equal(vim.api.nvim_win_get_cursor(source_win), original_cursor, 'exit must restore the source cursor')
    equal(vim.fn.maparg('j', 'n', false, true).callback, old_j, 'source mappings must remain untouched')
    equal(vim.api.nvim_buf_is_valid(viewer), false, 'exit must wipe the temporary buffer')
    equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), original_lines, 'source text must remain unchanged')
    equal(vim.api.nvim_buf_get_changedtick(buf), original_tick, 'navigation must not add changes to the source undo history')

    vim.cmd('MermaidFocus')
    equal(vim.api.nvim_win_get_cursor(0), saved_cursor, 're-entering focus must retain the diagram cursor')
    vim.cmd('MermaidFocus')
    equal(vim.api.nvim_get_current_buf(), buf, 'command must toggle focus from the viewer too')

    vim.cmd('MermaidFocus')
    float = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(source_win)
    assert(vim.wait(1000, function() return not vim.api.nvim_win_is_valid(float) end, 5), 'leaving the viewer must close it')
    equal(vim.api.nvim_get_current_win(), source_win, 'cleanup must not steal focus back from the user')

    vim.api.nvim_win_set_cursor(source_win, { 4, 0 })
    vim.cmd('MermaidFocus')
    viewer = vim.api.nvim_get_current_buf()
    vim.cmd('close')
    assert(vim.wait(1000, function() return not vim.api.nvim_buf_is_valid(viewer) end, 5), 'closing the window must wipe the scratch buffer')
    equal(vim.api.nvim_get_current_buf(), buf, 'native window close must return to Markdown')

    vim.api.nvim_win_set_cursor(source_win, { 4, 0 })
    vim.cmd('MermaidFocus')
    viewer = vim.api.nvim_get_current_buf()
    setup()
    equal(vim.api.nvim_buf_is_valid(viewer), false, 'setup must clean up an active viewer')
    equal(vim.api.nvim_get_current_buf(), buf, 'setup must return to the source')

    -- Short diagrams stay unchanged inline but can be focused for selection.
    output = { 'short diagram' }
    vim.api.nvim_buf_set_lines(buf, 4, 5, false, { 'A --> C' })
    display.render(buf, plugin.config)
    wait_for(buf, 'short diagram')
    equal(preview(buf), output, 'small inline diagrams must remain unchanged')
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd('MermaidFocus')
    equal(vim.api.nvim_get_current_line(), 'short diagram', 'short diagrams must support a real cursor too')
    keys('yyq')
    equal(vim.fn.getreg('"'), 'short diagram\n', 'native yy must copy a rendered line')
    equal(preview(buf), output, 'leaving a small diagram must remove the focus header')

    output = { string.rep('-', 200) .. ' wide end' }
    vim.api.nvim_buf_set_lines(buf, 4, 5, false, { 'A --> Wide' })
    display.render(buf, plugin.config)
    wait_for(buf, 'wide end')
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd('MermaidFocus')
    keys('$')
    assert(vim.fn.winsaveview().leftcol > 0, 'wide diagrams must support native horizontal scrolling')
    equal(vim.api.nvim_win_get_cursor(0)[2], #output[1] - 1, '$ must reach the end of wide rendered output')
    keys('0q')

    -- Unlimited inline output still gets a screen-sized, focusable window.
    output = {}
    for row = 1, 100 do output[row] = ('unlimited row %03d'):format(row) end
    setup({ max_preview_lines = false })
    vim.api.nvim_buf_set_lines(buf, 4, 5, false, { 'A --> D' })
    display.render(buf, plugin.config)
    wait_for(buf, 'unlimited row 100')
    equal(#preview(buf), 100, 'false must disable the inactive inline limit')
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd('MermaidFocus')
    assert(vim.api.nvim_win_get_height(0) < vim.api.nvim_win_get_height(source_win), 'focused window must fit on screen')
    keys('Gq')
    equal(#preview(buf), 100, 'exit must restore unlimited inline output')

    -- Renderer notices are outside the real navigable diagram buffer.
    notice = 'Structured report notice'
    vim.api.nvim_buf_set_lines(buf, 4, 5, false, { 'A --> Report' })
    setup({ placement = 'below', max_preview_lines = 8 })
    display.render(buf, plugin.config)
    wait_for(buf, notice)
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd('MermaidFocus')
    equal(vim.api.nvim_win_get_config(0).row, 3, 'below overlay must leave room for both notice and header')
    equal(vim.api.nvim_get_current_line(), 'unlimited row 001', 'viewer must contain output, not renderer metadata')
    equal(preview(buf)[1], notice, 'report notices must remain visible outside the viewer')
    keys('q')
    notice = nil

    -- Below-placement remains navigable when the fence ends at EOF.
    setup({ placement = 'below', max_preview_lines = 8 })
    vim.api.nvim_buf_set_lines(buf, 6, -1, false, {})
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    display.render(buf, plugin.config)
    vim.cmd('MermaidFocus')
    keys('G')
    equal(vim.api.nvim_get_current_line(), 'unlimited row 100', 'below-placement must reach the last row at EOF')
    keys('q')

    -- Identical source can share cached output, but not cursor/scroll state.
    local multi = new_buffer()
    source_win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(multi, 6, -1, false, { '', '```mermaid', 'flowchart TD', 'A --> B', '```' })
    setup({ max_preview_lines = 8 })
    wait_for(multi, 'diagram row 001')
    vim.cmd('MermaidFocus')
    keys('40jq')
    local first_page = preview(multi)[2]
    vim.api.nvim_win_set_cursor(0, { 9, 0 })
    display.render(multi, plugin.config)
    vim.cmd('MermaidFocus')
    equal(vim.api.nvim_win_get_cursor(0)[1], 1, 'second fence must have an independent cursor')
    keys('Gq')
    equal(preview(multi)[2], first_page, 'second fence navigation must not affect the first fence')
    equal(preview(multi)[11], 'diagram row 093', 'second fence must retain its own last page')

    -- Source edits release focus and cannot resurrect stale virtual lines.
    vim.cmd('MermaidFocus')
    viewer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(multi, 9, 10, false, { 'A --> Changed' })
    output = { 'changed diagram' }
    display.render(multi, plugin.config)
    wait_for(multi, 'changed diagram')
    equal(vim.api.nvim_buf_is_valid(viewer), false, 'source edits must wipe the obsolete viewer')
    equal(#preview(multi), 10, 'source edits must not resurrect obsolete extmarks')

    -- Reflow an open viewer, retaining its real cursor and immutable output.
    vim.api.nvim_win_set_cursor(source_win, { 4, 0 })
    vim.cmd('MermaidFocus')
    float = vim.api.nvim_get_current_win()
    keys('G')
    plugin.config.max_preview_lines = 5
    display.render(multi, plugin.config)
    equal(vim.api.nvim_win_get_height(float), 5, 'viewer must follow a changed row budget')
    equal(vim.api.nvim_win_get_cursor(float)[1], 100, 'reflow must preserve the real diagram cursor')
    vim.api.nvim_buf_set_lines(multi, 0, -1, false, { '# No diagrams' })
    display.render(multi, plugin.config)
    equal(preview(multi), {}, 'removing a focused fence must leave no obsolete preview')
    equal(vim.api.nvim_win_is_valid(float), false, 'removing a fence must close its viewer')

    local config = require('render-markdown-mermaid.config')
    for _, value in ipairs({ 0, -1, 'invalid', math.huge }) do
        equal(config.merge({ max_preview_lines = value }).max_preview_lines, '75%', 'invalid height must fall back to the default percentage')
    end
    print('inline cursor navigation: all checks passed')
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
else
    vim.cmd('qa!')
end
