local M = {}

---@param value string?
---@return string
local function basename(value)
    if not value or value == '' then
        return ''
    end
    return vim.fs.basename(value)
end

local KNOWN_RENDERERS = {
    bm = true,
    termaid = true,
    ['mermaid-ascii'] = true,
    selkie = true,
    ['merman-cli'] = true,
}

---@param command string[]
---@return string, integer?
local function renderer_kind(command)
    command = command or {}
    for index, part in ipairs(command) do
        local name = basename(part)
        if KNOWN_RENDERERS[name] then
            return name, index
        end
    end
    return basename(command[1]), nil
end

---@param stdout string
---@return string[]
local function output_lines(stdout)
    local output = stdout:gsub('\r\n', '\n'):gsub('\n+$', '')
    if output == '' then
        return {}
    end

    return vim.split(output, '\n', { plain = true })
end

---@param config table
---@return boolean
local function is_ascii_mode(config)
    return config.mode == 'ascii'
end

---@param config table
---@return string[]
local function mermaid_ascii_command(config)
    local command = vim.deepcopy(config.cmd)
    vim.list_extend(command, {
        '-f',
        '-',
        '-p',
        tostring(config.cli.border_padding),
        '-x',
        tostring(config.cli.padding_x),
        '-y',
        tostring(config.cli.padding_y),
    })
    if is_ascii_mode(config) then
        command[#command + 1] = '-a'
    end
    return command
end

---@param config table
---@return string[]
local function bm_command(config)
    local command = vim.deepcopy(config.cmd)
    local _, executable_index = renderer_kind(command)
    local subcommand_index = executable_index and executable_index + 1 or 2
    if command[subcommand_index] ~= 'ascii' then
        table.insert(command, subcommand_index, 'ascii')
    end
    vim.list_extend(command, {
        '--box-padding',
        tostring(config.cli.border_padding),
        '--padding-x',
        tostring(config.cli.padding_x),
        '--padding-y',
        tostring(config.cli.padding_y),
    })
    if is_ascii_mode(config) then
        command[#command + 1] = '--ascii'
    end
    return command
end

---@param config table
---@return string[]
local function termaid_command(config)
    local command = vim.deepcopy(config.cmd)
    vim.list_extend(command, {
        '--padding-x',
        tostring(config.cli.padding_x),
        '--padding-y',
        tostring(config.cli.padding_y),
    })
    if is_ascii_mode(config) then
        command[#command + 1] = '--ascii'
    end
    return command
end

---Selkie renders character art with box-drawing nodes and braille edge
---routing. It has no plain-ASCII mode or padding flags, so `mode` and `cli`
---padding do not apply.
---@param config table
---@return string[]
local function selkie_command(config)
    local command = vim.deepcopy(config.cmd)
    vim.list_extend(command, { '-i', '-', '-e', 'ascii', '-o', '-' })
    return command
end

---Merman admits the `auto` layout profile (canonical, then a compact retry)
---only for flowcharts and sequence diagrams; other families reject the flag.
local MERMAN_COMPACT_FAMILIES = {
    flowchart = true,
    graph = true,
    sequenceDiagram = true,
}

---@param source string
---@return boolean
local function merman_compact_family(source)
    local lines = vim.split(source, '\n', { plain = true })
    local start = 1
    if vim.trim(lines[1] or '') == '---' then
        for index = 2, #lines do
            if vim.trim(lines[index]) == '---' then
                start = index + 1
                break
            end
        end
    end
    for index = start, #lines do
        local line = vim.trim(lines[index])
        if line ~= '' and not line:match('^%%') then
            return MERMAN_COMPACT_FAMILIES[line:match('^(%S+)') or ''] == true
        end
    end
    return false
end

---Build the merman-cli argv. `--ascii-report` makes stdout a JSON envelope
---(ASCII output schema 3) whose `text` field carries the rendering together
---with `projection` and `outcome`, so diagrams can be distinguished from
---structured text and width fallbacks.
---@param config table
---@param width integer?
---@param source string
---@return string[]
local function merman_command(config, width, source)
    local command = vim.deepcopy(config.cmd)
    vim.list_extend(command, {
        'render',
        '-',
        '--format',
        is_ascii_mode(config) and 'ascii' or 'unicode',
        '--output',
        '-',
        '--ascii-color',
        'plain',
    })
    if width then
        vim.list_extend(command, {
            '--ascii-max-width',
            tostring(width),
            '--ascii-overflow',
            'fallback',
        })
        if merman_compact_family(source) then
            vim.list_extend(command, { '--ascii-layout-profile', 'auto' })
        end
    end
    command[#command + 1] = '--ascii-report'
    return command
end

---@param config table
---@param width integer?
---@param source string
---@return string[]
function M.command(config, width, source)
    if renderer_kind(config.cmd) == 'bm' then
        return bm_command(config)
    end
    if renderer_kind(config.cmd) == 'termaid' then
        return termaid_command(config)
    end
    if renderer_kind(config.cmd) == 'selkie' then
        return selkie_command(config)
    end
    if renderer_kind(config.cmd) == 'merman-cli' then
        return merman_command(config, width, source or '')
    end
    return mermaid_ascii_command(config)
end

---@param stdout string
---@return table?
local function decode_json(stdout)
    if not stdout or stdout == '' then
        return nil
    end
    local ok, decoded = pcall(vim.json.decode, stdout)
    if ok and type(decoded) == 'table' then
        return decoded
    end
    return nil
end

---Extract rendered lines from a merman-cli result. With `--ascii-report`
---active, stdout is a JSON envelope carrying the text; older builds without
---the flag emit the rendering directly, so fall back to raw stdout. Returns
---the lines plus an optional notice when the payload is not a diagram.
---@param result table
---@param config table
---@return string[]?, string?
local function merman_output(result, config)
    local report = decode_json(result.stdout)
    local text = report and report.text or result.stdout
    local lines = output_lines(text or '')
    if #lines == 0 then
        return nil, nil
    end
    local notice = nil
    if report then
        if report.outcome == 'fallback' or report.fallback_attempted then
            notice = config.ui.fallback
        elseif report.projection == 'structured_text' then
            notice = config.ui.report
        end
    end
    return lines, notice
end

---@param result table
---@param kind string
---@return string
local function render_error(result, kind)
    if kind == 'merman-cli' then
        -- Failures use ASCII error-report schema 1 on stderr, which carries a
        -- terminal-safe message alongside a stable code and category.
        local report = decode_json(result.stderr or '')
        if report and type(report.error) == 'table' and type(report.error.message) == 'string' then
            if report.error.message ~= '' then
                return report.error.message
            end
        end
    end
    local error = vim.trim(result.stderr or '')
    if error == '' then
        error = vim.trim(result.stdout or '')
    end
    if error == '' then
        return ('%s returned no output'):format(kind ~= '' and kind or 'renderer')
    end
    return error
end

---@param config table
---@param source string
---@param width integer?
---@param callback fun(result: table)
function M.render(config, source, width, callback)
    local command = M.command(config, width, source)
    local kind = renderer_kind(command)
    vim.system(command, {
        stdin = source,
        text = true,
        timeout = config.timeout,
    }, function(result)
        vim.schedule(function()
            if result.code == 0 and result.stdout and result.stdout ~= '' then
                if kind == 'merman-cli' then
                    local lines, notice = merman_output(result, config)
                    if lines then
                        callback({ ok = true, output = lines, notice = notice })
                        return
                    end
                else
                    local lines = output_lines(result.stdout)
                    if #lines > 0 then
                        callback({ ok = true, output = lines })
                        return
                    end
                end
            end

            callback({
                ok = false,
                error = render_error(result, kind),
            })
        end)
    end)
end

return M
