-- Inline previews are virtual lines. Focus overlays them with a real scratch
-- buffer, letting Neovim own cursor motions, selection, search, and scrolling.
local M = {}
local buffers = {}
local focus = nil

local function paint(entry)
    local active = focus and focus.entry == entry
    local last = active and #entry.lines or math.max(1, #entry.lines - entry.height + 1)
    entry.first = math.max(1, math.min(entry.first, last))
    local ending = math.min(#entry.lines, entry.first + entry.height - 1)
    local visible = {}
    for row = entry.first, ending do
        visible[#visible + 1] = entry.lines[row]
    end
    if active then
        -- Native scrolling may leave blank rows below EOF. Keep the inline
        -- rectangle stable underneath the focused window in that case.
        while #visible < entry.height do visible[#visible + 1] = '' end
    end
    local indicator = nil
    if active or #entry.lines > entry.height then
        local key = entry.focus_key == false and ':MermaidFocus'
            or (entry.focus_key == '<CR>' and 'Enter' or entry.focus_key or 'Enter')
        local hint = active and 'Vim motions | q/Esc exit' or key .. ' to navigate'
        indicator = ('Mermaid %d-%d/%d | %s'):format(entry.first, ending, #entry.lines, hint)
    end
    entry.draw(visible, indicator)
end

local function save_position(state)
    if state.win and vim.api.nvim_win_is_valid(state.win)
        and vim.api.nvim_win_get_buf(state.win) == state.buf then
        state.entry.view = vim.api.nvim_win_call(state.win, vim.fn.winsaveview)
        state.entry.first = state.entry.view.topline
    end
end

---@param restore_view? boolean Restore the source view only on explicit exit.
function M.blur(restore_view)
    local previous = focus
    if not previous then return end
    save_position(previous)
    focus = nil
    if previous.win and vim.api.nvim_win_is_valid(previous.win) then
        pcall(vim.api.nvim_win_close, previous.win, true)
    end
    if previous.buf and vim.api.nvim_buf_is_valid(previous.buf) then
        pcall(vim.api.nvim_buf_delete, previous.buf, { force = true })
    end
    previous.entry.height = previous.entry.limit
    if vim.api.nvim_buf_is_valid(previous.source_buf) then
        paint(previous.entry)
    end
    if restore_view and vim.api.nvim_win_is_valid(previous.source_win)
        and vim.api.nvim_win_get_buf(previous.source_win) == previous.source_buf then
        vim.api.nvim_set_current_win(previous.source_win)
        vim.fn.winrestview(previous.source_view)
    end
end

local function layout(state)
    local entry = state.entry
    local source = state.source_win
    local info = vim.fn.getwininfo(source)[1]
    local width = math.max(1, vim.api.nvim_win_get_width(source) - info.textoff)
    local padding = math.min(entry.padding, math.floor((width - 1) / 2))
    return {
        relative = 'win',
        win = source,
        bufpos = { entry.anchor_row, 0 },
        row = entry.above and -entry.height or 2 + entry.notice_lines,
        col = padding,
        width = math.max(1, width - 2 * padding),
        height = entry.height,
        focusable = true,
        style = 'minimal',
        border = 'none',
        zindex = 60,
    }
end

local function align_source(state)
    vim.api.nvim_win_call(state.source_win, function()
        vim.cmd(state.entry.above and 'normal! zb' or 'normal! zt')
    end)
end

local function focused_height(entry, source)
    return math.max(1, math.min(entry.limit, #entry.lines, vim.api.nvim_win_get_height(source) - 4))
end

---Start a display pass. Identical fences share cached output, not view state.
function M.begin(buf)
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    local state = buffers[buf]
    if not state or state.tick ~= tick then
        if focus and focus.source_buf == buf then M.blur() end
        state = { tick = tick, entries = {} }
        buffers[buf] = state
    end
    state.seen = {}
end

---@param buf integer
---@param block table
---@param lines string[]
---@param height integer
---@param draw fun(visible: string[], indicator: string?)
function M.show(buf, block, lines, height, draw)
    local state = buffers[buf]
    local entry = state.entries[block.start_row]
    if not entry or entry.key ~= block.key then
        if focus and focus.entry == entry then M.blur() end
        entry = { first = 1, key = block.key }
        state.entries[block.start_row] = entry
    end
    entry.start_row = block.start_row
    entry.end_row = block.end_row
    entry.above = block.above
    entry.anchor_row = block.anchor_row
    entry.preview_row = block.preview_row
    entry.focus_key = block.focus_key
    entry.notice_lines = block.notice_lines or 0
    entry.padding = block.padding or 0
    entry.lines = lines
    entry.limit = height
    entry.height = height
    entry.draw = draw
    state.seen[block.start_row] = true
    local active = focus and focus.entry == entry
    if active then
        entry.height = focused_height(entry, focus.source_win)
        save_position(focus)
    end
    paint(entry)
    if active and focus.win and vim.api.nvim_win_is_valid(focus.win) then
        focus.busy = true
        align_source(focus)
        local config = layout(focus)
        if not vim.deep_equal(config, focus.layout) then
            vim.api.nvim_win_set_config(focus.win, config)
            focus.layout = config
        end
        focus.busy = false
    end
end

function M.finish(buf)
    local state = buffers[buf]
    for row, entry in pairs(state.entries) do
        if not state.seen[row] then
            if focus and focus.entry == entry then M.blur() end
            state.entries[row] = nil
        end
    end
end

local function entry_at_cursor(buf)
    local state = buffers[buf]
    if not state or state.tick ~= vim.api.nvim_buf_get_changedtick(buf) then return nil end
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local anchor = nil
    for _, entry in pairs(state.entries) do
        -- An actual fence takes precedence when previews are adjacent.
        if row >= entry.start_row and row < entry.end_row then return entry end
        if row == entry.anchor_row or row == entry.preview_row then anchor = entry end
    end
    return anchor
end

---Read-only lookup: safe to call from an expression mapping under textlock.
function M.can_focus(buf)
    return entry_at_cursor(buf) ~= nil
end

---Focus a real read-only buffer over the rendered fence under the cursor.
---Only q/Esc are mapped; all navigation is Neovim's ordinary buffer behavior.
function M.focus(buf)
    if focus then
        if focus.win and vim.api.nvim_win_is_valid(focus.win) then
            M.blur(true)
            return
        end
        -- :close can remove the float before the scheduled leave handler
        -- runs. Do not treat that stale state as a request to toggle off.
        M.blur()
    end
    local entry = entry_at_cursor(buf)
    if not entry then
        vim.notify('Place the cursor on a rendered Mermaid block or its preview anchor.', vim.log.levels.INFO)
        return
    end
    local source = vim.api.nvim_get_current_win()
    local state_focus = {
        source_buf = buf,
        source_win = source,
        source_view = vim.fn.winsaveview(),
        entry = entry,
        busy = true,
    }
    focus = state_focus
    entry.height = focused_height(entry, source)
    local anchor = math.min(entry.anchor_row + 1, vim.api.nvim_buf_line_count(buf))
    vim.api.nvim_win_set_cursor(source, { anchor, 0 })
    paint(entry)
    align_source(state_focus)

    local ok, err = pcall(function()
        local scratch = vim.api.nvim_create_buf(false, true)
        state_focus.buf = scratch
        vim.bo[scratch].bufhidden = 'wipe'
        vim.bo[scratch].swapfile = false
        vim.api.nvim_buf_set_lines(scratch, 0, -1, false, entry.lines)
        vim.bo[scratch].modifiable = false
        vim.bo[scratch].readonly = true
        vim.bo[scratch].filetype = 'mermaid-preview'
        for _, key in ipairs({ 'q', '<Esc>' }) do
            vim.keymap.set('n', key, function() M.blur(true) end, {
                buffer = scratch, nowait = true, desc = 'Return to Markdown',
            })
        end
        state_focus.layout = layout(state_focus)
        local win = vim.api.nvim_open_win(scratch, false, state_focus.layout)
        state_focus.win = win
        vim.wo[win].wrap = false
        vim.wo[win].foldenable = false
        vim.wo[win].signcolumn = 'no'
        vim.wo[win].scrollbind = false
        vim.wo[win].cursorbind = false
        vim.wo[win].winblend = 0
        vim.wo[win].winhighlight = 'Normal:RenderMarkdownCode'
        vim.api.nvim_set_current_win(win)
        vim.fn.winrestview(entry.view or { lnum = entry.first, topline = entry.first })
    end)
    state_focus.busy = false
    if not ok then
        M.blur(true)
        vim.notify('Could not focus Mermaid diagram: ' .. tostring(err), vim.log.levels.ERROR)
        return
    end
    M.check()
end

---Mirror the real window's visible range back to the inline preview. This
---observes native motions; it does not implement or remap them.
function M.check()
    if not focus or focus.busy then return end
    if not vim.api.nvim_win_is_valid(focus.source_win)
        or not vim.api.nvim_buf_is_valid(focus.source_buf)
        or not vim.api.nvim_win_is_valid(focus.win)
        or vim.api.nvim_get_current_win() ~= focus.win
        or vim.api.nvim_get_current_buf() ~= focus.buf then
        M.blur()
        return
    end
    save_position(focus)
    paint(focus.entry)
end

function M.changed(buf)
    if focus and focus.source_buf == buf then M.blur() end
end

function M.clear(buf)
    if focus and (not buf or focus.source_buf == buf) then M.blur() end
    if buf then
        buffers[buf] = nil
    else
        buffers = {}
    end
end

return M
