local cache = require('render-markdown-mermaid.cache')
local renderer = require('render-markdown-mermaid.renderer')
local util = require('render-markdown-mermaid.util')
local scroll = require('render-markdown-mermaid.scroll')
local config_mod = require('render-markdown-mermaid.config')

local M = {
    ns = vim.api.nvim_create_namespace('render-markdown-mermaid.nvim'),
    timers = {},
}
local configs = {}

local function stop_timer(buf)
    local timer = M.timers[buf]
    if not timer then
        return
    end
    M.timers[buf] = nil
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
end

local QUERY = vim.treesitter.query.parse(
    'markdown',
    [[
      (fenced_code_block
        (info_string
          (language) @lang)
        (code_fence_content) @content) @code
    ]]
)

local function is_supported(buf)
    local ft = vim.bo[buf].filetype
    return ft == 'markdown' or ft == 'mdx' or ft == 'markdown.mdx'
end

local function current_row(buf)
    local current = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(current) == buf then
        return vim.api.nvim_win_get_cursor(current)[1] - 1
    end
    local wins = vim.fn.win_findbuf(buf)
    if #wins == 0 then
        return nil
    end
    return vim.api.nvim_win_get_cursor(wins[1])[1] - 1
end

local function in_insert_mode()
    local mode = vim.api.nvim_get_mode().mode or ''
    return mode:match('^[iR]') ~= nil
end

local function window_width(buf)
    local win = vim.fn.win_findbuf(buf)[1]
    if not win then
        return nil
    end
    local info = vim.fn.getwininfo(win)
    local textoff = info and info[1] and info[1].textoff or 0
    return math.max(vim.api.nvim_win_get_width(win) - textoff, 20)
end

---Resolve the configured render width for renderers that accept one.
---@param config table
---@param buf integer
---@return integer?
local function resolve_width(config, buf)
    if config.width == nil then
        return nil
    end
    if config.width ~= 'auto' then
        return config.width
    end
    return window_width(buf)
end

local function preview_height(config, buf, total)
    if config.max_preview_lines == false then
        return math.max(1, total)
    end
    -- Extmarks are buffer-local and shared by all windows showing the buffer.
    -- Fit the smallest window rather than clipping the diagram in a split.
    local height = vim.o.lines
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        height = math.min(height, vim.api.nvim_win_get_height(win))
    end
    local limit = config.max_preview_lines
    local percent = type(limit) == 'string' and tonumber(limit:match('^(%d+%.?%d*)%%$')) or nil
    local requested = percent and math.floor(height * percent / 100) or limit
    return math.max(1, math.min(requested, height - 4))
end

local function preview_padding(config, buf, lines)
    if not config.center then return 0 end
    local width = vim.o.columns
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        local info = vim.fn.getwininfo(win)[1]
        width = math.min(width, vim.api.nvim_win_get_width(win) - info.textoff)
    end
    local widest = 0
    for _, line in ipairs(lines) do
        widest = math.max(widest, vim.fn.strdisplaywidth(line))
    end
    return math.max(0, math.floor((width - widest) / 2))
end

local function cursor_inside_block(row, start_row, end_row)
    return row and row >= start_row and row < end_row
end

local function node_text(node, buf)
    local text = util.node_text(node, buf)
    if text ~= '' then
        return vim.trim(text)
    end
    local start_row, _, end_row = node:range()
    return vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, start_row, end_row, false), '\n'))
end

local function key_for(source, config, width)
    return util.hash(vim.json.encode({
        source = source,
        cmd = config.cmd,
        mode = config.mode,
        cli = config.cli,
        width = width,
    }))
end

local function preview_anchor(config, start_row, end_row, replacing)
    if replacing then
        if start_row > 0 then
            return start_row - 1, false
        end
        return end_row, true
    end
    if config.placement == 'below' then
        return end_row, true
    end
    return start_row, true
end

local function render_preview(buf, row, lines, above, notice, indicator, padding, id)
    local virt_lines = {}
    if notice and notice ~= '' then
        virt_lines[#virt_lines + 1] = { { notice, 'RenderMarkdownMermaidNotice' } }
    end
    if indicator then
        virt_lines[#virt_lines + 1] = { { indicator, 'RenderMarkdownMermaidScroll' } }
    end
    local aligned = {}
    local prefix = string.rep(' ', padding)
    for _, line in ipairs(lines) do aligned[#aligned + 1] = prefix .. line end
    -- Extmarks are shared between windows: fill the widest text area and let
    -- Neovim clip excess spaces in narrower splits. Recompute on every redraw.
    local width = 0
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        local info = vim.fn.getwininfo(win)[1]
        width = math.max(width, vim.api.nvim_win_get_width(win) - info.textoff)
    end
    vim.list_extend(virt_lines, util.to_virt_lines(aligned, width))
    return vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
        id = id,
        virt_lines = virt_lines,
        virt_lines_above = above,
        priority = 200,
        strict = false,
    })
end

local function render_message(buf, row, text, highlight, above)
    vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
        virt_lines = { { { text, highlight } } },
        virt_lines_above = above,
        priority = 200,
        strict = false,
    })
end

local function conceal_source(buf, start_row, end_row)
    vim.api.nvim_buf_set_extmark(buf, M.ns, start_row, 0, {
        end_row = end_row,
        end_col = 0,
        conceal = '',
        priority = 199,
        strict = false,
    })
end

local function conceal_lines(buf, start_row, end_row)
    vim.api.nvim_buf_set_extmark(buf, M.ns, start_row, 0, {
        end_row = end_row,
        end_col = 0,
        conceal_lines = '',
        priority = 199,
        strict = false,
    })
end

local function blocks(buf)
    local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
    if not ok or not parser then
        return {}
    end
    local tree = parser:parse()[1]
    if not tree then
        return {}
    end

    local root = tree:root()
    local result = {}
    for _, match, _ in QUERY:iter_matches(root, buf, 0, -1) do
        local lang_node = match[1] and match[1][1] or nil
        local content_node = match[2] and match[2][1] or nil
        local code_node = match[3] and match[3][1] or nil
        if code_node and lang_node and content_node then
            local language = vim.trim(util.node_text(lang_node, buf))
            if language == 'mermaid' then
                result[#result + 1] = {
                    code = code_node,
                    content = content_node,
                }
            end
        end
    end
    return result
end

function M.render(buf, config)
    if not vim.api.nvim_buf_is_valid(buf) or not is_supported(buf) then
        return
    end

    configs[buf] = config

    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    scroll.begin(buf)
    local row = current_row(buf)
    local editing = in_insert_mode()
    local width = resolve_width(config, buf)

    for _, block in ipairs(blocks(buf)) do
        local start_row, _, end_row = block.code:range()
        local line_count = end_row - start_row
        if line_count <= config.max_block_lines then
            local source = node_text(block.content, buf)
            if source ~= '' then
                local key = key_for(source, config, width)
                local entry = config.cache and cache.get(key) or nil
                local cursor_inside = cursor_inside_block(row, start_row, end_row)
                local replacing = config.replace and not editing and not cursor_inside

                if replacing then
                    conceal_lines(buf, start_row, end_row)
                elseif config.hide_source and not cursor_inside then
                    conceal_source(buf, start_row, end_row)
                end

                local preview_row, preview_above = preview_anchor(config, start_row, end_row, replacing)

                if entry and entry.status == 'done' then
                    local mark = nil
                    local padding = preview_padding(config, buf, entry.lines)
                    local focus_row = config.placement == 'below' and end_row - 1 or start_row
                    local focus_above = config.placement ~= 'below'
                    if replacing then
                        focus_row, focus_above = preview_row, preview_above
                    end
                    scroll.show(buf, {
                        start_row = start_row,
                        end_row = end_row,
                        key = key,
                        above = focus_above,
                        anchor_row = focus_row,
                        preview_row = preview_row,
                        focus_key = config.focus_key,
                        notice_lines = entry.notice and entry.notice ~= '' and 1 or 0,
                        padding = padding,
                        renderer = config_mod.renderer_name(config.cmd),
                    }, entry.lines, preview_height(config, buf, #entry.lines), function(visible, indicator)
                        if vim.api.nvim_buf_is_valid(buf) then
                            -- A full render may already have removed this mark
                            -- while releasing focus on an edited/removed fence.
                            if mark and #vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, mark, {}) == 0 then
                                return
                            end
                            mark = render_preview(buf, preview_row, visible, preview_above, entry.notice, indicator, padding, mark)
                        end
                    end)
                elseif entry and entry.status == 'error' then
                    render_message(buf, preview_row, config.ui.error, 'RenderMarkdownMermaidError', preview_above)
                else
                    if not entry then
                        cache.set(key, { status = 'pending' })
                        renderer.render(config, source, width, function(result)
                            if not vim.api.nvim_buf_is_valid(buf) then
                                return
                            end
                            if result.ok then
                                cache.set(key, { status = 'done', lines = result.output, notice = result.notice })
                            else
                                cache.set(key, { status = 'error', error = result.error })
                            end
                            vim.schedule(function()
                                -- A renderer cycle may have superseded this
                                -- request. Cache its result, but never let an
                                -- old backend repaint the current preview.
                                if configs[buf] == config then M.render(buf, config) end
                            end)
                        end)
                    end
                    render_message(buf, preview_row, config.ui.pending, 'RenderMarkdownMermaidPending', preview_above)
                end
            end
        end
    end
    scroll.finish(buf)
end

function M.schedule(buf, config, delay)
    configs[buf] = config
    stop_timer(buf)

    local next_timer = vim.uv.new_timer()
    M.timers[buf] = next_timer
    next_timer:start(delay, 0, vim.schedule_wrap(function()
        if M.timers[buf] ~= next_timer then
            return
        end
        stop_timer(buf)
        M.render(buf, config)
    end))
end

function M.clear(buf)
    configs[buf] = nil
    scroll.clear(buf)
    if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    end
    stop_timer(buf)
end

return M
