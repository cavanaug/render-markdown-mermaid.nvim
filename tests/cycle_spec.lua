-- Run from the repo root: nvim --headless -u NONE -l tests/cycle_spec.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require('render-markdown-mermaid.config')
local available = { selkie = true, bm = true, termaid = true, ['mermaid-ascii'] = true, ['merman-cli'] = true }
config.available_renderers = function() return vim.deepcopy(available) end
local requests = {}
local held = {}
local hold = false
package.loaded['render-markdown-mermaid.renderer'] = {
    render = function(opts, _, width, callback)
        local request = { cmd = vim.deepcopy(opts.cmd), width = width, callback = callback }
        requests[#requests + 1] = request
        if hold then
            held[#held + 1] = request
        else
            vim.schedule(function() callback({ ok = true, output = { opts.cmd[#opts.cmd] .. ' diagram' } }) end)
        end
    end,
}
local plugin = require('render-markdown-mermaid')
local display = require('render-markdown-mermaid.display')
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
local function equal(actual, expected, message)
    assert(vim.deep_equal(actual, expected), message .. '\nactual: ' .. vim.inspect(actual))
end
local function preview(buf)
    local lines = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, display.ns, 0, -1, { details = true })) do
        for _, line in ipairs(mark[4].virt_lines or {}) do lines[#lines + 1] = line[1][1] end
    end
    return table.concat(lines, '\n')
end
local function wait_for(buf, name)
    assert(vim.wait(1000, function() return preview(buf):find(name .. ' diagram', 1, true) ~= nil end, 5),
        'preview never showed renderer ' .. name .. ': ' .. preview(buf))
end
local function setup(opts)
    plugin.setup(vim.tbl_extend('force', { auto_setup_render_markdown = false, debounce = 0, center = false }, opts or {}))
end
local function keys(input)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(input, true, false, true), 'xt', false)
end

local function run()
    local buf = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()
    vim.wo.scrolloff = 7
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# Test', '```mermaid', 'graph TD', 'A --> B', '```' })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    local source = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    setup()
    wait_for(buf, 'selkie')
    local source_tab = function() end
    vim.keymap.set('n', '<Tab>', source_tab, { buffer = buf })
    local first_count = #requests
    vim.cmd('MermaidCycle')
    equal(plugin.config.cmd, { 'bm' }, 'cycle must select the next installed renderer')
    wait_for(buf, 'bm')
    assert(notifications[#notifications]:find('bm', 1, true), 'cycle must report the selected renderer')
    equal(#requests, first_count + 1, 'new backend must render immediately')
    vim.cmd('MermaidCycle!')
    equal(plugin.config.cmd, { 'selkie' }, 'bang must cycle backwards')
    wait_for(buf, 'selkie')
    equal(#requests, first_count + 1, 'switching back must reuse the backend-specific cache')
    vim.cmd('MermaidCycle!')
    equal(plugin.config.cmd, { 'merman-cli' }, 'reverse cycle must wrap around')
    equal(plugin.config.width, 'auto', 'Merman must get its default width fitting when cycled into')
    wait_for(buf, 'merman-cli')
    assert(type(requests[#requests].width) == 'number', 'Merman must receive a resolved width')
    vim.cmd('MermaidCycle')
    equal(plugin.config.cmd, { 'selkie' }, 'forward cycle must wrap around')
    equal(plugin.config.width, nil, 'Merman automatic width must not leak into other backends')
    wait_for(buf, 'selkie')

    -- Visit every backend explicitly, including mermaid-ascii between
    -- termaid and Merman, in both directions.
    for _, name in ipairs({ 'bm', 'termaid', 'mermaid-ascii', 'merman-cli', 'selkie' }) do
        vim.cmd('MermaidCycle')
        equal(plugin.config.cmd, { name }, 'forward cycle must include every installed backend')
        wait_for(buf, name)
    end
    for _, name in ipairs({ 'merman-cli', 'mermaid-ascii', 'termaid', 'bm', 'selkie' }) do
        vim.cmd('MermaidCycle!')
        equal(plugin.config.cmd, { name }, 'reverse cycle must include every installed backend')
        wait_for(buf, name)
    end

    available = { selkie = true, termaid = true }
    vim.cmd('MermaidCycle')
    equal(plugin.config.cmd, { 'termaid' }, 'cycle must skip missing executables')
    wait_for(buf, 'termaid')
    keys('<Plug>(MermaidCycle)')
    equal(plugin.config.cmd, { 'selkie' }, 'Plug mapping must cycle forwards')
    wait_for(buf, 'selkie')
    keys('<Plug>(MermaidCycleBack)')
    equal(plugin.config.cmd, { 'termaid' }, 'Plug mapping must cycle backwards')
    wait_for(buf, 'termaid')
    vim.cmd('MermaidFocus')
    local viewer = vim.api.nvim_get_current_buf()
    keys('<Tab>')
    equal(plugin.config.cmd, { 'selkie' }, 'Tab inside the diagram must cycle forwards')
    equal(vim.api.nvim_buf_is_valid(viewer), true, 'cycling must keep the existing viewer')
    equal(vim.api.nvim_get_current_buf(), viewer, 'cycling must update the viewer in place')
    wait_for(buf, 'selkie')
    assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() ~= buf end, 5),
        'cycling must restore diagram navigation when the new output arrives')
    equal(vim.api.nvim_get_current_line(), 'selkie diagram', 'new viewer must contain the selected backend output')
    assert(preview(buf):find('| selkie |', 1, true), 'active header must identify the selected renderer')
    keys('<S-Tab>')
    equal(plugin.config.cmd, { 'termaid' }, 'Shift-Tab inside the diagram must cycle backwards')
    wait_for(buf, 'termaid')
    assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() ~= buf end, 5), 'reverse cycling must also reopen navigation')
    keys('q')
    vim.cmd('MermaidCycle')
    wait_for(buf, 'selkie')

    -- Cycle changes must not rerun setup or overwrite user configuration.
    equal(plugin.config.center, false, 'cycle must preserve preview configuration')
    equal(vim.fn.maparg('<Tab>', 'n', false, true).callback, source_tab, 'source Tab mappings must remain unchanged')
    equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source, 'cycle must not edit Markdown')
    available = { selkie = true }
    local old_config = plugin.config
    vim.cmd('MermaidCycle')
    equal(plugin.config, old_config, 'one available backend must be a no-op')
    available = {}
    vim.cmd('MermaidCycle')
    equal(plugin.config, old_config, 'no installed backends must leave the configuration intact')
    assert(notifications[#notifications]:find('No', 1, true), 'missing backends must produce a clear message')

    available = { selkie = true, ['merman-cli'] = true }
    setup({ width = false })
    vim.cmd('MermaidCycle')
    equal(plugin.config.width, nil, 'explicit width=false must remain disabled on Merman')
    setup({ width = 60 })
    vim.cmd('MermaidCycle')
    equal(plugin.config.width, 60, 'explicit width budget must survive cycling')

    -- Retain explicit executable paths/wrappers on return to their backend.
    setup({ cmd = { 'env', '/opt/renderers/selkie' } })
    vim.cmd('MermaidCycle')
    equal(plugin.config.cmd, { 'merman-cli' }, 'wrapped executable must identify its backend')
    vim.cmd('MermaidCycle')
    equal(plugin.config.cmd, { 'env', '/opt/renderers/selkie' }, 'cycling back must preserve the configured command')

    -- A late callback from the old backend may populate its cache but must
    -- not repaint over the renderer selected by a more recent cycle.
    available = { selkie = true, bm = true }
    setup()
    hold = true
    vim.api.nvim_buf_set_lines(buf, 3, 4, false, { 'A --> NewSource' })
    display.render(buf, plugin.config)
    assert(#held > 0, 'test must hold an outstanding renderer request')
    hold = false
    vim.cmd('MermaidCycle')
    wait_for(buf, 'bm')
    held[#held].callback({ ok = true, output = { 'selkie diagram' } })
    vim.wait(30, function() return false end, 5)
    assert(preview(buf):find('bm diagram', 1, true), 'late old-backend callback must not overwrite the new preview')
    vim.cmd('MermaidCycle!')
    wait_for(buf, 'selkie')

    -- Leaving during a slow backend switch must not reopen the viewer later.
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd('MermaidFocus')
    hold = true
    -- Change the selected backend's CLI settings to ensure this is a fresh
    -- render rather than an existing cached request.
    plugin.config.cli.padding_x = 42
    keys('<Tab>')
    assert(vim.wait(1000, function() return #held > 1 end, 5), 'test must hold the newly cycled backend')
    hold = false
    vim.api.nvim_set_current_win(source_win)
    vim.api.nvim_win_set_cursor(0, { 1, 1 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
    equal(vim.wo.scrolloff, 7, 'cancelled viewer re-entry must restore source scrolloff')
    held[#held].callback({ ok = true, output = { 'bm diagram' } })
    wait_for(buf, 'bm')
    equal(vim.api.nvim_get_current_buf(), buf, 'a delayed backend result must not steal focus after the user moves')
    vim.cmd('MermaidCycle!')
    wait_for(buf, 'selkie')

    -- All loaded Markdown buffers should use the session-wide selection.
    local other = vim.api.nvim_create_buf(true, false)
    vim.bo[other].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(other, 0, -1, false, source)
    display.render(other, plugin.config)
    wait_for(other, 'selkie')
    vim.cmd('MermaidCycle')
    wait_for(buf, 'bm')
    wait_for(other, 'bm')
    print('renderer cycling: all checks passed')
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
else
    vim.cmd('qa!')
end
