local M = {}
local DEFAULT_RENDERERS = { 'selkie', 'bm', 'termaid', 'mermaid-ascii' }
-- selkie always draws with Unicode box-drawing characters; when the user
-- explicitly requests plain-ASCII output, prefer backends that honor it.
local ASCII_RENDERERS = { 'bm', 'termaid', 'mermaid-ascii', 'selkie' }
local ALL_RENDERERS = { 'selkie', 'bm', 'termaid', 'mermaid-ascii', 'merman-cli' }
local VALID_MODES = {
    unicode = true,
    ascii = true,
}
local VALID_PLACEMENTS = {
    above = true,
    below = true,
}

local function has_executable(command)
    return vim.fn.executable(command) == 1
end

---@return table<string, boolean>
function M.available_renderers()
    local available = {}
    for _, command in ipairs(ALL_RENDERERS) do
        available[command] = has_executable(command)
    end
    return available
end

---@param cmd? string[]
---@param available? table<string, boolean>
---@param mode? string
---@return string[]
function M.resolve_cmd(cmd, available, mode)
    if cmd and cmd[1] then
        return vim.deepcopy(cmd)
    end
    available = available or M.available_renderers()
    local renderers = mode == 'ascii' and ASCII_RENDERERS or DEFAULT_RENDERERS
    for _, command in ipairs(renderers) do
        if available[command] then
            return { command }
        end
    end
    return { DEFAULT_RENDERERS[1] }
end

---Normalize the configured render width. Only renderers that accept a width
---limit (merman-cli) consume it; nil disables width handling entirely.
---@param width any
---@return integer|'auto'|nil
function M.resolve_width(width)
    if width == nil or width == false then
        return nil
    end
    if width == 'auto' then
        return 'auto'
    end
    if type(width) == 'number' then
        return math.max(math.floor(width), 20)
    end
    return nil
end

M.default = {
    mode = 'unicode',
    placement = 'above',
    replace = false,
    cmd = { 'selkie' },
    auto_setup_render_markdown = true,
    debounce = 150,
    timeout = 2000,
    cache = true,
    hide_source = false,
    max_block_lines = 200,
    max_preview_lines = '75%',
    center = true,
    focus_key = '<CR>',
    render_markdown = {
        file_types = { 'markdown', 'mdx', 'markdown.mdx' },
    },
    cli = {
        border_padding = 1,
        padding_x = 5,
        padding_y = 5,
    },
    ui = {
        pending = '󱎫 Mermaid rendering...',
        error = '󱂅 Mermaid render failed',
        report = '󰛈 Structured text report (not a diagram)',
        fallback = '󰛈 Diagram too wide; structured text fallback',
    },
}

---@param opts? table
---@return table
function M.merge(opts)
    local merged = vim.tbl_deep_extend('force', {}, M.default, opts or {})
    local user_placement = opts and opts.placement or nil
    local user_mode = opts and opts.mode or nil

    if VALID_PLACEMENTS[user_placement] then
        merged.placement = user_placement
    elseif not VALID_PLACEMENTS[merged.placement] then
        merged.placement = M.default.placement
    end

    if VALID_MODES[user_mode] then
        merged.mode = user_mode
    elseif not VALID_MODES[merged.mode] then
        merged.mode = M.default.mode
    end

    merged.cli = merged.cli or {}
    merged.cli.ascii = nil

    if merged.focus_key ~= false and (type(merged.focus_key) ~= 'string' or merged.focus_key == '') then
        merged.focus_key = M.default.focus_key
    end

    if merged.max_preview_lines ~= false then
        local height = merged.max_preview_lines
        local percent = type(height) == 'string' and tonumber(height:match('^(%d+%.?%d*)%%$')) or nil
        if percent and percent > 0 and percent <= 100 then
            merged.max_preview_lines = height
        elseif type(height) == 'number' and height >= 1 and height < math.huge then
            merged.max_preview_lines = math.floor(height)
        else
            merged.max_preview_lines = M.default.max_preview_lines
        end
    end

    local has_user_cmd = opts and opts.cmd and opts.cmd[1]
    merged._cmd_source = has_user_cmd and 'user' or 'auto'
    if merged._cmd_source == 'auto' or not merged.cmd or not merged.cmd[1] then
        merged.cmd = M.resolve_cmd(nil, nil, merged.mode)
    end

    local user_width = nil
    if opts and opts.width ~= nil then
        user_width = opts.width
    end
    merged.width = M.resolve_width(merged.width)
    -- merman-cli is the only renderer that consumes a width limit; default it
    -- to the live window width so its compact/overflow contracts engage. An
    -- explicit `width = false` opts out of width fitting entirely.
    if merged.width == nil and user_width == nil and vim.fs.basename(merged.cmd[1] or '') == 'merman-cli' then
        merged.width = 'auto'
    end
    return merged
end

return M
