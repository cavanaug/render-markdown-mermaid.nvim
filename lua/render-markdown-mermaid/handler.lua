local cache = require('render-markdown-mermaid.cache')
local extmarks = require('render-markdown-mermaid.extmarks')
local renderer = require('render-markdown-mermaid.renderer')
local util = require('render-markdown-mermaid.util')

local M = {}

local QUERY = vim.treesitter.query.parse(
    'markdown',
    [[
      (fenced_code_block
        (info_string
          (language) @lang)
        (code_fence_content) @content) @code
    ]]
)

local function source_from_node(node, buf)
    local text = util.node_text(node, buf)
    if text ~= '' then
        return vim.trim(text)
    end

    local start_row, _, end_row = node:range()
    local lines = vim.api.nvim_buf_get_lines(buf, start_row, end_row, false)
    return vim.trim(table.concat(lines, '\n'))
end

---@param buf integer
---@param code_node TSNode
---@param content_node TSNode
---@param config table
---@return render.md.Mark[]
local function marks_for_block(buf, code_node, content_node, config)
    local start_row, _, end_row = code_node:range()
    local line_count = end_row - start_row
    if line_count > config.max_block_lines then
        return {}
    end

    local source = source_from_node(content_node, buf)
    if source == '' then
        return {}
    end

    local key = util.hash(vim.json.encode({
        source = source,
        mode = config.mode,
        cli = config.cli,
    }))

    local entry = config.cache and cache.get(key) or nil
    if entry and entry.status == 'done' then
        return extmarks.diagram(start_row, end_row, entry.lines, config.mode)
    end
    if entry and entry.status == 'error' then
        return extmarks.message(end_row - 1, config.ui.error, 'RenderMarkdownMermaidError')
    end

    if not entry then
        cache.set(key, { status = 'pending' })
        renderer.render(config, source, function(result)
            if result.ok then
                cache.set(key, { status = 'done', lines = result.output })
            else
                cache.set(key, { status = 'error', error = result.error })
            end
            vim.api.nvim_exec_autocmds('User', {
                pattern = 'RenderMarkdownMermaidUpdate',
                buffer = buf,
                modeline = false,
            })
        end)
    end

    return extmarks.message(end_row - 1, config.ui.pending, 'RenderMarkdownMermaidPending')
end

---@param ctx render.md.handler.Context
---@param config table
---@return render.md.Mark[]
function M.parse(ctx, config)
    local marks = {}

    for _, match, _ in QUERY:iter_matches(ctx.root, ctx.buf, 0, -1) do
        local lang_node = match[1] and match[1][1] or nil
        local content_node = match[2] and match[2][1] or nil
        local code_node = match[3] and match[3][1] or nil
        if code_node and lang_node and content_node then
            local language = vim.trim(util.node_text(lang_node, ctx.buf))
            if language == 'mermaid' then
                vim.list_extend(marks, marks_for_block(ctx.buf, code_node, content_node, config))
            end
        end
    end

    return marks
end

return M
