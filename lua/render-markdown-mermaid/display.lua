local cache = require('render-markdown-mermaid.cache')
local renderer = require('render-markdown-mermaid.renderer')
local util = require('render-markdown-mermaid.util')

local M = {
    ns = vim.api.nvim_create_namespace('render-markdown-mermaid.nvim'),
    timers = {},
}

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

local function key_for(source, config)
    return util.hash(vim.json.encode({
        source = source,
        cmd = config.cmd,
        mode = config.mode,
        cli = config.cli,
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

local function render_preview(buf, row, lines, above)
    vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
        virt_lines = util.to_virt_lines(lines),
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

    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    local row = current_row(buf)
    local editing = in_insert_mode()

    for _, block in ipairs(blocks(buf)) do
        local start_row, _, end_row = block.code:range()
        local line_count = end_row - start_row
        if line_count <= config.max_block_lines then
            local source = node_text(block.content, buf)
            if source ~= '' then
                local key = key_for(source, config)
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
                    render_preview(buf, preview_row, entry.lines, preview_above)
                elseif entry and entry.status == 'error' then
                    render_message(buf, preview_row, config.ui.error, 'RenderMarkdownMermaidError', preview_above)
                else
                    if not entry then
                        cache.set(key, { status = 'pending' })
                        renderer.render(config, source, function(result)
                            if not vim.api.nvim_buf_is_valid(buf) then
                                return
                            end
                            if result.ok then
                                cache.set(key, { status = 'done', lines = result.output })
                            else
                                cache.set(key, { status = 'error', error = result.error })
                            end
                            vim.schedule(function()
                                M.render(buf, config)
                            end)
                        end)
                    end
                    render_message(buf, preview_row, config.ui.pending, 'RenderMarkdownMermaidPending', preview_above)
                end
            end
        end
    end
end

function M.schedule(buf, config, delay)
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
    if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    end
    stop_timer(buf)
end

return M
